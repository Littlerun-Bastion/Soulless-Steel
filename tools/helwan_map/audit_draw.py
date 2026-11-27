"""Finds drawn detail that lies where it should not: on another building,
on a ground obstacle (pipe, pool), on road concrete, or (roof items) off its
own roof.

  python audit_draw.py <project> <work dir> [--window x0,y0,x1,y1] [--city <cache>]
  python audit_draw.py --analyse <work dir>

The first form runs run_all.main with Layers._put wrapped: every
triangle the generator writes (after Layers.add_tris has applied its clips:
ruined roofs' holes and fragments, Layers.within) is recorded with its
sublayer, the building
being drawn (Layers.bid, -1 for the district drawers and the ground) and a
tag naming the drawing function (the first caller outside the drawing kit:
module.qualname, with the next meaningful caller after "<"). The roads,
the final footprints and the obstacles are kept too. Everything goes to
<work dir>/audit_raw.pkl, then the analysis runs.

The analysis samples each triangle (its centre, points towards each corner,
more on large triangles) on 0.5 m rasters of:
  buildings  footprints shrunk by EDGE_M, by building id
  obstacles  ground obstacles shrunk by EDGE_M
  roads      road concrete (not rail) shrunk by EDGE_M
and counts, per tag and sublayer, the triangles with a sample on another
building, on an obstacle, on a road, and (roofs) off their own footprint
grown by ROOF_SLACK_M. Talls count only their ground-level parts (every
vertex under TALL_GROUND_M). The report is <work dir>/audit.txt and
audit.json: per tag, the counts, the area hit and the places hit most, so a
reviewer can tell intended overlaps (road markings on roads, ground fills
under buildings) from bugs.
"""
import json
import os
import pickle
import sys
from collections import defaultdict

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

RES = 0.5
EDGE_M = 0.35
ROOF_SLACK_M = 0.4
TALL_GROUND_M = 1.5
PX = 20.0

# Frames of the drawing kit: a tag names the first caller outside them.
KIT_MODULES = {"style", "kit", "solar", "equipment"}
KIT_PREFIXES = ("Layers.", "Batch.", "Roof.", "Quads.", "counted")
KIT_FUNCS = {"outlined", "triangulate", "draw_halo", "_wrap", "pave", "fence", "wall", "disc"}


def _tag(frame):
    out = []
    f = frame
    while f is not None and len(out) < 2:
        mod = os.path.splitext(os.path.basename(f.f_code.co_filename))[0]
        q = getattr(f.f_code, "co_qualname", f.f_code.co_name)
        if mod == "audit_draw" or "mask_drawers" in q:
            f = f.f_back
            continue
        skip = (mod in KIT_MODULES and (q.startswith(KIT_PREFIXES) or q.split(".")[0] in KIT_FUNCS
                                        or mod in ("kit", "solar", "equipment")))
        if not skip:
            out.append(f"{mod}.{q}")
        f = f.f_back
    return " < ".join(out) if out else "?"


def record(project, work, window=None, city=None):
    import style
    import run_all
    import buildings as bl

    recs = defaultdict(list)
    tag_ids = {}
    orig = style.Layers._put

    def put(self, sub, key, tris, grey, alpha, heights=None):
        if len(tris):
            t = _tag(sys._getframe(1))
            tid = tag_ids.setdefault(t, len(tag_ids))
            arr = np.asarray(tris, np.float32).reshape(-1, 3, 2)
            hmax = None
            if sub == "talls":
                h = heights if heights is not None else np.full(arr.shape[:2], self.height, np.float32)
                hmax = np.asarray(h, np.float32).reshape(-1, 3).max(1)
            recs[(tid, sub, int(self.bid))].append((arr, hmax))
        return orig(self, sub, key, tris, grey, alpha, heights)

    kept = {}
    orig_roads = style.draw_roads

    def draw_roads(L, roads, water):
        kept["roads"] = [g for g, *_, kind, _ in roads if not kind.startswith("rail:")]
        return orig_roads(L, roads, water)

    orig_build = bl.build_layers

    def build_layers(water, roads, buildings, *a, **k):
        L = orig_build(water, roads, buildings, *a, **k)
        kept["footprints"] = [b.poly for b in buildings]
        kept["kinds"] = [b.kind for b in buildings]
        return L

    style.Layers._put = put
    style.draw_roads = draw_roads
    bl.build_layers = build_layers
    try:
        run_all.main(project, work, window, False, city)
    finally:
        style.Layers._put = orig
        style.draw_roads = orig_roads
        bl.build_layers = orig_build
    packed = {}
    for key, parts in recs.items():
        tris = np.concatenate([p[0] for p in parts])
        h = None if parts[0][1] is None else np.concatenate([p[1] for p in parts])
        packed[key] = (tris, h)
    raw = {"tags": {v: k for k, v in tag_ids.items()}, "recs": packed, "roads": kept.get("roads", []),
           "footprints": kept.get("footprints", []), "kinds": kept.get("kinds", []), "window": window}
    with open(os.path.join(work, "audit_raw.pkl"), "wb") as fh:
        pickle.dump(raw, fh, protocol=pickle.HIGHEST_PROTOCOL)
    return raw


def _read_obstacles(path):
    """(kind, outline (n, 2) metres) per obstacle in obstacles.bin."""
    out = []
    with open(path, "rb") as fh:
        data = fh.read()
    n = int(np.frombuffer(data, np.uint32, 1, 0)[0])
    o = 4
    for _ in range(n):
        kind, k = np.frombuffer(data, np.uint32, 2, o)
        o += 8
        xy = np.frombuffer(data, np.float32, int(k) * 2, o).reshape(-1, 2) / PX
        o += int(k) * 8
        out.append((int(kind), xy.astype(np.float64)))
    return out


class Grid:
    def __init__(self, x0, y0, x1, y1):
        self.x0, self.y0 = x0, y0
        self.w = int(np.ceil((x1 - x0) / RES)) + 1
        self.h = int(np.ceil((y1 - y0) / RES)) + 1

    def pix(self, pts):
        return [((x - self.x0) / RES, (y - self.y0) / RES) for x, y in pts]

    def burn(self, geoms, ids=None, shrink=EDGE_M):
        from style import polys
        img = Image.new("I", (self.w, self.h), -1)
        d = ImageDraw.Draw(img)
        for i, g in enumerate(geoms):
            g2 = g.buffer(-shrink) if shrink else g
            for p in polys(g2):
                if p.area < RES * RES:
                    continue
                d.polygon(self.pix(p.exterior.coords), fill=int(ids[i] if ids is not None else i))
                for hole in p.interiors:
                    d.polygon(self.pix(hole.coords), fill=-1)
        return np.asarray(img, np.int32)

    def look(self, raster, pts):
        ix = np.floor((pts[:, 0] - self.x0) / RES).astype(np.int64)
        iy = np.floor((pts[:, 1] - self.y0) / RES).astype(np.int64)
        ok = (ix >= 0) & (iy >= 0) & (ix < self.w) & (iy < self.h)
        out = np.full(len(pts), -1, np.int32)
        out[ok] = raster[iy[ok], ix[ok]]
        return out


def _samples(tris):
    """(n, k, 2) sample points per triangle: the centre and points 70% of
    the way to each corner, plus a 4 x 4 barycentric grid on triangles over
    4 m2."""
    c = tris.mean(1, keepdims=True)
    pts = [c[:, 0]] + [c[:, 0] + 0.7 * (tris[:, i] - c[:, 0]) for i in range(3)]
    s = np.stack(pts, 1)
    e1, e2 = tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    area = 0.5 * np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0])
    return s, area


def analyse(work):
    from shapely.geometry import Polygon
    with open(os.path.join(work, "audit_raw.pkl"), "rb") as fh:
        raw = pickle.load(fh)
    fps = raw["footprints"]
    kinds = raw["kinds"]
    obs = _read_obstacles(os.path.join(work, "obstacles.bin"))
    obs_polys = [Polygon(xy) for _, xy in obs if len(xy) >= 3]
    import shapely
    from gen_city import HALF_M
    G = Grid(-HALF_M, -HALF_M, HALF_M, HALF_M)
    B = G.burn(fps)
    O = G.burn(obs_polys)
    R = G.burn(raw["roads"], ids=np.zeros(len(raw["roads"]), int))
    grown = {}
    report = {}
    for (tid, sub, bid), (tris, hmax) in raw["recs"].items():
        tag = raw["tags"][tid]
        if sub == "talls":
            sel = hmax < TALL_GROUND_M
            tris = tris[sel]
        if len(tris) == 0:
            continue
        s, area = _samples(tris.astype(np.float64))
        n, k = s.shape[:2]
        flat = s.reshape(-1, 2)
        b = G.look(B, flat).reshape(n, k)
        o = G.look(O, flat).reshape(n, k)
        r = G.look(R, flat).reshape(n, k)
        other_b = (b >= 0) & (b != bid)
        hit_b = other_b.any(1)
        hit_o = (o >= 0).any(1)
        hit_r = (r >= 0).any(1)
        if sub == "roofs" and bid >= 0:
            if bid not in grown:
                grown[bid] = fps[bid].buffer(ROOF_SLACK_M)
                shapely.prepare(grown[bid])
            off = ~shapely.contains_xy(grown[bid], flat[:, 0], flat[:, 1]).reshape(n, k).all(1)
        else:
            off = np.zeros(n, bool)
        key = f"{sub}\t{tag}\t{'bld' if bid >= 0 else 'free'}"
        rep = report.setdefault(key, {"tris": 0, "area": 0.0, "on_building": 0, "on_building_m2": 0.0,
                                      "on_obstacle": 0, "on_obstacle_m2": 0.0, "on_road": 0, "on_road_m2": 0.0,
                                      "off_roof": 0, "off_roof_m2": 0.0, "where": defaultdict(int),
                                      "hit_kinds": defaultdict(int)})
        rep["tris"] += n
        rep["area"] += float(area.sum())
        for name, m in (("on_building", hit_b), ("on_obstacle", hit_o), ("on_road", hit_r), ("off_roof", off)):
            rep[name] += int(m.sum())
            rep[name + "_m2"] += float(area[m].sum())
        bad = hit_b | hit_o | off
        if bad.any():
            cen = s[bad, 0]
            for cx, cy in np.round(cen / 25.0).astype(int) * 25:
                rep["where"][(int(cx), int(cy))] += 1
            for bb in np.unique(b[hit_b][other_b[hit_b]]):
                rep["hit_kinds"][kinds[bb] if 0 <= bb < len(kinds) else "?"] += 1
    out = {}
    for key, rep in report.items():
        w = sorted(rep["where"].items(), key=lambda t: -t[1])[:8]
        rep["where"] = [[x, y, c] for (x, y), c in w]
        rep["hit_kinds"] = dict(sorted(rep["hit_kinds"].items(), key=lambda t: -t[1])[:8])
        out[key] = rep
    with open(os.path.join(work, "audit.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1)
    rows = sorted(out.items(), key=lambda t: -(t[1]["on_building_m2"] + t[1]["on_obstacle_m2"] + t[1]["off_roof_m2"]))
    with open(os.path.join(work, "audit.txt"), "w", encoding="utf-8") as fh:
        fh.write("sub\ttag\tdrawn\ttris\tarea_m2\ton_bld\ton_bld_m2\ton_obs\ton_obs_m2\ton_road\ton_road_m2"
                 "\toff_roof\toff_roof_m2\thit_kinds\twhere\n")
        for key, r in rows:
            fh.write(f"{key}\t{r['tris']}\t{r['area']:.0f}\t{r['on_building']}\t{r['on_building_m2']:.1f}"
                     f"\t{r['on_obstacle']}\t{r['on_obstacle_m2']:.1f}\t{r['on_road']}\t{r['on_road_m2']:.1f}"
                     f"\t{r['off_roof']}\t{r['off_roof_m2']:.1f}\t{json.dumps(r['hit_kinds'])}"
                     f"\t{json.dumps(r['where'][:4])}\n")
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--analyse":
        analyse(args[1])
        sys.exit(0)
    win = None
    if "--window" in args:
        i = args.index("--window")
        win = tuple(float(v) for v in args[i + 1].split(","))
        del args[i:i + 2]
    city = None
    if "--city" in args:
        i = args.index("--city")
        city = args[i + 1]
        del args[i:i + 2]
    record(args[0], args[1], win, city)
    analyse(args[1])
