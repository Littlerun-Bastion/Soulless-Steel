"""Generates the Helwan map.

Usage: python run_all.py <repo>/project <work dir> [--window x0,y0,x1,y1]
                         [--reuse] [--city <city_cache.pkl>]

Reads inputs/map.json (map size, border band, reference image and its fit),
the reference image, inputs/osm.geojson and sprite_catalogue.json next to
this script, and the KeepOut and DistrictZones areas in helwan_master.tscn
if it exists.
Writes:
  <project>/assets/images/map/helwan/   ground mask, macro tone, reference
                                        image (greyscale, as the generator
                                        reads it)
  <project>/database/maps/helwan_generated.tscn   (always)
  <project>/database/maps/helwan_master.tscn      (only if missing)
  <work dir>/   mesh, footprint, district, obstacle, prop and salvage files
                for build_meshes.gd, and stats.json (counts and timings)
Then run build_meshes.gd in Godot (see README.md).

--window x0,y0,x1,y1  builds only the street blocks and large roofs that
                      touch this box (map-frame metres, origin at the map
                      centre, y down) and writes only to the work dir, not
                      to the project. For quick previews with
                      render_preview.py.
--reuse               reuses the city layout (roads, roofs, lots) saved by
                      the last run in the same work dir, and starts at the
                      districts. Only when the inputs have not changed.
--city <file>         uses the city layout saved by another run (its work
                      dir's city_cache.pkl). With --window and a full run's
                      cache, the districts are the full map's, and only the
                      window's content is built and drawn: the quickest way
                      to look at a part of the map exactly as a full run
                      makes it.
"""
import json
import os
import pickle
import sys
import time
from gc import collect as collect_garbage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np
from PIL import Image
from shapely.geometry import Point, Polygon, box
from shapely.ops import linemerge

import buildings as bl
import civic
import district_life
import districts
import fabric
import farmland
import gen_city as gc
import gen_ground as gg
import gen_scene as gs
import industrial
import infra
import landmarks
import market
import markers
import master_io
import military
import obstacles
import props
import ruins
import salvage
import sites
import style
from features import compute
from geo import load
from site_ctx import Site
from zones import classify


def peak_memory_mb():
    """The process's peak memory (working set) in MB, or -1 if unknown."""
    try:
        import ctypes
        from ctypes import wintypes

        class Counters(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                        ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]

        c = Counters()
        c.cb = ctypes.sizeof(Counters)
        k32 = ctypes.windll.kernel32
        k32.GetCurrentProcess.restype = wintypes.HANDLE
        info = ctypes.windll.psapi.GetProcessMemoryInfo
        info.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        info(k32.GetCurrentProcess(), ctypes.byref(c), c.cb)
        return c.PeakWorkingSetSize / 2 ** 20
    except (AttributeError, OSError):
        try:
            import resource
            return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
        except ImportError:
            return -1.0


class Clock:
    def __init__(self):
        self.t0 = self.t = time.time()
        self.steps = {}

    def lap(self, name):
        now = time.time()
        self.steps[name] = round(now - self.t, 1)
        print(f"[{now - self.t0:7.1f} s] {name} ({now - self.t:.1f} s)", flush=True)
        self.t = now


def overlap_counts(buildings):
    """Overlapping footprint pairs (buildings.overlapping_pairs), by
    district and by the stages that made the two buildings."""
    names = {0: "residential", 1: "industrial", 2: "market", 3: "farmland"}
    out = {"pairs": 0, "by_district": {}, "by_stage": {}}
    for i, j, _ in bl.overlapping_pairs(buildings):
        a, b = buildings[i], buildings[j]
        out["pairs"] += 1
        d = names.get(a.district, str(a.district))
        out["by_district"][d] = out["by_district"].get(d, 0) + 1
        s = " / ".join(sorted((a.opts.get("stage", "?"), b.opts.get("stage", "?"))))
        out["by_stage"][s] = out["by_stage"].get(s, 0) + 1
    return out


def main(project, work, window=None, reuse=False, city=None):
    clock = Clock()
    os.makedirs(work, exist_ok=True)
    osm = os.path.join(HERE, "inputs", "osm.geojson")
    maps_dir = os.path.join(project, "database", "maps")
    master_path = os.path.join(maps_dir, "helwan_master.tscn")
    preview = window is not None
    if not preview:
        os.makedirs(maps_dir, exist_ok=True)

    keep_out = master_io.keep_out_union(master_path)
    painted = master_io.read_district_zones(master_path)
    print("keep-out areas:", len(master_io.read_keep_outs(master_path)), "district zones:", len(painted), flush=True)

    feats = load(osm)
    f = compute(feats)
    zone, rects = classify(f)
    clock.lap("image and zones")
    cache = os.path.join(work, "city_cache.pkl")
    if city or (reuse and os.path.exists(cache)):
        with open(city or cache, "rb") as fh:
            water, roads, big, lots, viaducts, blocks = pickle.load(fh)
    else:
        win = box(*window) if preview else None
        water, roads, big, lots, viaducts, blocks = gc.build(feats, f, zone, rects, keep_out, window=win)
        with open(cache, "wb") as fh:
            pickle.dump((water, roads, big, lots, viaducts, blocks), fh, protocol=pickle.HIGHEST_PROTOCOL)
    clock.lap("city layout")

    tidy = style.tidy_big_roofs(big)
    D = districts.build(feats, f, zone, roads, [g for g, _ in tidy] + [l for l, _, _ in lots], painted)
    clock.lap("districts")
    full_layout = {"roads": roads, "blocks": blocks, "big": [g for g, _ in tidy], "lots": [l for l, _, _ in lots]}
    if preview and city:
        win = box(*window)
        near = win.buffer(120)
        tidy = [t for t in tidy if t[0].intersects(win)]
        lots = [t for t in lots if t[0].intersects(win)]
        blocks = [b for b in blocks if b.intersects(win)]
        roads = [r for r in roads if r[0].intersects(near)]
        water = water.intersection(near)

    site = Site(water, roads, blocks, viaducts, D, keep_out, f, zone)
    site.feats = feats
    site.markers = master_io.read_markers(master_path)
    # The whole map's layout, also in a window run with --city: the site
    # modules choose their places over the whole map from it, then build only
    # the ones that touch site.window (None in a full run), so a window
    # preview shows what the full run makes there.
    site.full_layout = full_layout
    site.window = box(*window) if preview else None
    site.buildings = [bl.Building(g, mv, "big") for g, mv in tidy] + [bl.Building(l, mv, "house") for l, mv, _ in lots]
    site.salvage = salvage.Salvage(keep_out)
    site.obstacles = obstacles.Obstacles()
    site.props = props.Props(keep_out)
    for b in site.buildings:
        b.opts["stage"] = "osm roofs" if b.kind == "big" else "lots"

    def tag(stage):
        for b in site.buildings:
            b.opts.setdefault("stage", stage)

    industrial.build(site)
    tag("industrial")
    clock.lap("industrial")
    market.build(site)
    tag("market")
    clock.lap("market")
    farmland.build(site)
    tag("farmland")
    clock.lap("farmland")
    military.build(site)
    tag("military")
    clock.lap("military")
    # The site modules run after the district modules and claim their land
    # (Site.claim); each one builds only on land still free, so the order is
    # their priority. Their props are set pieces (props.SetPiece).
    site.props.set_piece = True
    for name, module in (("landmarks", landmarks), ("infra", infra), ("civic", civic), ("fabric", fabric),
                         ("sites", sites)):
        site.stats[name] = module.build(site)
        tag(name)
        clock.lap(name)
    site.props.set_piece = False
    for b in site.buildings:
        b.district = D.of_geom(b.poly)
    site.stats["overlaps"] = {"before": overlap_counts(site.buildings)}
    site.buildings, trimmed, dropped = bl.resolve_overlaps(site.buildings)
    site.stats["overlaps"].update({"trimmed": trimmed, "dropped": dropped, "after": overlap_counts(site.buildings)})
    ruins.assign_states(site.buildings)

    layers = bl.build_layers(water, roads, site.buildings, site.drawers, site.salvage)
    manifest, tris = layers.write(work)
    clock.lap("meshes")
    print("buildings", len(site.buildings), "roads", len(roads), "meshes", len(manifest), "triangles", tris, flush=True)
    # The mesh data is on disk now; keep only the footprints, to save memory
    # for the steps below on big maps.
    footprints = layers.footprints
    del layers
    collect_garbage()

    if not preview:
        img = os.path.join(project, "assets", "images", "map", "helwan")
        os.makedirs(img, exist_ok=True)
        Image.fromarray((gg.macro_tone(f, gc.HALF_M) * 255).astype(np.uint8)).save(os.path.join(img, "macro_tone.png"))
        drawn = [(b.poly, 0, 0) for b in site.buildings if b.state != ruins.COLLAPSED]
        Image.fromarray(gg.ground_mask(f, zone, drawn, gc.HALF_M)).save(os.path.join(img, "ground_mask.png"))
        Image.fromarray((np.clip(f["mk"] / max(float(f["mk"].max()), 1e-6), 0, 1) * 255).astype(np.uint8)).save(
            os.path.join(img, "mockup_reference.png"))

        overheads = []
        if viaducts:
            merged = linemerge(viaducts).intersection(gc.FRAME)
            for line in getattr(merged, "geoms", [merged]):
                if line.length > 20:
                    overheads.append([(x * gc.PX_PER_M, y * gc.PX_PER_M) for x, y in line.simplify(0.5).coords])
        gs.write_generated(os.path.join(maps_dir, "helwan_generated.tscn"), manifest, props.CATALOGUE, overheads)

        if not os.path.exists(master_path):
            footprints_m = [b.poly for b in site.buildings]
            exits, starts, spawns, cysts = markers.pick(roads, footprints_m, water)
            px = lambda pts: [(x * gc.PX_PER_M, y * gc.PX_PER_M) for x, y in pts]
            gs.write_master(master_path, px(exits), px(starts), px(spawns), px(cysts))
            print("wrote", master_path)
        else:
            print("kept", master_path)
        clock.lap("images and scenes")

    P = props.build(footprints, roads, water, gc.viaduct_clearance(viaducts), [g for g, _ in tidy], f, zone,
                    keep_out, extra_solid=site.solid_extra + [site.obstacles.union()], P=site.props,
                    salvage=site.salvage,
                    life=lambda P, S, rd, jn, rng: site.stats.__setitem__(
                        "district_life", district_life.place(P, S, D, rd, jn, rng)))
    P.write(os.path.join(work, "props.json"))
    with open(os.path.join(work, "landmarks.json"), "w", encoding="utf-8") as fh:
        json.dump({"items": [{**lm, "x": lm["x"] * gc.PX_PER_M, "y": lm["y"] * gc.PX_PER_M,
                              "radius": lm["radius"] * gc.PX_PER_M,
                              "outline": [[x * gc.PX_PER_M, y * gc.PX_PER_M] for x, y in lm["outline"]]}
                             for lm in site.landmarks]}, fh, indent=1, ensure_ascii=False)
    site.salvage.write(os.path.join(work, "salvage.json"))
    site.obstacles.write(os.path.join(work, "obstacles.bin"))
    D.write(os.path.join(work, "districts.bin"))
    clock.lap("props, salvage, obstacles")

    hit = [name for name, x, y in site.markers
           if any(Polygon(pts).contains(Point(x, y)) for _, pts in site.obstacles.items)]
    site.stats["markers"] = {"checked": len(site.markers), "in_an_obstacle": hit}
    stats = {
        "buildings": len(site.buildings),
        "buildings_by_state": {},
        "buildings_by_district": {},
        "buildings_by_district_and_state": {},
        "district_cells": D.counts(),
        "obstacles": site.obstacles.counts(),
        "salvage": site.salvage.counts(),
        "props": {},
        "districts": site.stats,
        "triangles": int(tris),
        "meshes": len(manifest),
        "work_dir_mb": round(sum(os.path.getsize(os.path.join(work, n)) for n in os.listdir(work)
                                 if n.endswith(".bin")) / 2 ** 20, 1),
        "seconds": clock.steps,
        "total_seconds": round(time.time() - clock.t0, 1),
        "peak_memory_mb": round(peak_memory_mb()),
    }
    for b in site.buildings:
        st, di = bl.STATE_NAMES[b.state], districts.NAMES[b.district]
        stats["buildings_by_state"][st] = stats["buildings_by_state"].get(st, 0) + 1
        stats["buildings_by_district"][di] = stats["buildings_by_district"].get(di, 0) + 1
        k = f"{di}/{st}"
        stats["buildings_by_district_and_state"][k] = stats["buildings_by_district_and_state"].get(k, 0) + 1
    for k, *_ in P.items:
        stats["props"][props.KINDS[k]] = stats["props"].get(props.KINDS[k], 0) + 1
    stats["set_piece_props"] = {}
    for it in P.items:
        if isinstance(it, props.SetPiece):
            name = props.KINDS[it[0]]
            stats["set_piece_props"][name] = stats["set_piece_props"].get(name, 0) + 1
    with open(os.path.join(work, "stats.json"), "w", encoding="utf-8") as fh:
        json.dump(stats, fh, indent=1)
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    args = sys.argv[1:]
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
    reuse = "--reuse" in args
    args = [a for a in args if a != "--reuse"]
    main(args[0], args[1], win, reuse, city)
