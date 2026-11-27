"""Prepares prop sprites for the game and writes sprite_catalogue.json.

Usage: python prep_sprites.py inputs/sprites <repo>/project

Sources are named <group>_<name>.png:
  tree_branches_*  slices of a bare tree; the game layers 2-3 per tree
  bush_*           scrub
  vehicle_*        top-down vehicles, drawn with the front facing up
  stall_*          market stalls, drawn with the counter along x and the
                   front facing +y; stall_<name>_broken.png is the broken
                   stall on the same canvas and scale
  hut_*            industrial huts and cabins, long side along x;
                   hut_<name>_broken.png is the ruin on the same canvas
  clutter_*        small yard items (drums, pallets, a cable reel ...)

Outputs go to assets/images/map/props/:
  tree_<n>.png, bush_<n>.png   resized (trees 512 px, bushes 256 px)
  vehicle_<name>.png           turned to face +x (Godot rotation 0), size kept
  stall_<name>.png, stall_<name>_broken.png   copied as they are
  hut_<name>.png, hut_<name>_broken.png, clutter_<name>.png   copied as they are

Vehicle sprites are not all drawn to one scale, so VEHICLES gives each one's
real length and its prop kind. Its width follows from the sprite's shape.
mass_kg and shot_block (the chance a shot passing through it is stopped) go
to the VehicleField. source is the salvage source kind the vehicle is (see
salvage.py), or none. STALLS gives each stall's real counter length and its
variant order (0 lean-to, 1 canopy, 2 table with crates, 3 hand cart).

The buses, military vehicles, container truck, containers and stalls are
placeholders drawn by make_placeholders.py until the real art exists.

sprite_catalogue.json: {kind: [{file, span, length_m, width_m, ...}]}. span is
the fraction of the image width the drawn body covers, so the game can size
a sprite from the spawn size. Stall entries also name their "broken" file,
which shares the intact sprite's canvas, scale and span. The hut list holds
the intact huts (HUTS order) and then their ruins ("ruin": true) in the same
order: a hut spawned with a ruin's variant is a ruin from the start (see
StallField). A vehicle with spawn weight 0 (the tanker, the dump truck) is
never picked at random; the generator places it by name.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

OUT_DIR = "assets/images/map/props"

# name: kind, real length (m), mass (kg), shot block chance, spawn weight,
# salvage source kind (or None)
VEHICLES = {
    "hatchback": ("vehicle", 4.0, 950, 0.5, 1.0, None),
    "sports": ("vehicle", 4.4, 1300, 0.5, 0.35, None),
    "estate": ("vehicle", 4.8, 1500, 0.5, 1.0, None),
    "suv": ("vehicle", 4.9, 2200, 0.55, 0.8, None),
    "pickup": ("vehicle", 5.3, 2000, 0.55, 0.8, None),
    "ambulance": ("vehicle", 6.0, 3500, 0.65, 0.12, None),
    "minibus": ("truck", 7.0, 4200, 0.7, 1.0, None),
    "fire_engine": ("truck", 9.5, 14000, 0.85, 0.25, None),
    "container_truck": ("truck", 16.5, 15000, 0.85, 0.3, "container_truck"),
    "tanker": ("truck", 10.0, 22000, 0.85, 0.0, "tanker"),
    "dump_truck": ("truck", 8.5, 20000, 0.85, 0.0, "dump_truck"),
    "bus_city": ("bus", 12.0, 12000, 0.8, 1.0, "bus"),
    "bus_coach": ("bus", 12.2, 13000, 0.8, 0.6, "bus"),
    "tank_west": ("military", 9.8, 60000, 0.95, 0.5, "tank"),
    "tank_east": ("military", 9.5, 45000, 0.95, 0.5, "tank"),
    "apc": ("military", 7.6, 14000, 0.9, 1.0, "military_vehicle"),
    "military_truck": ("military", 8.0, 9000, 0.75, 1.0, "military_vehicle"),
    "container_20ft_a": ("container", 6.06, 25000, 0.95, 1.0, "shipping_container"),
    "container_20ft_b": ("container", 6.06, 25000, 0.95, 1.0, "shipping_container"),
    "container_40ft": ("container", 12.19, 30000, 0.95, 0.6, "shipping_container"),
    "metro_cab": ("railcar", 20.0, 40000, 0.95, 0.0, "railcar"),
    "metro_car": ("railcar", 20.0, 38000, 0.95, 0.0, "railcar"),
    "boxcar": ("railcar", 14.0, 28000, 0.95, 0.0, "freight_wagon"),
    "flatcar": ("railcar", 14.0, 25000, 0.5, 0.0, None),
    "flatcar_container": ("railcar", 14.0, 52000, 0.95, 0.0, "shipping_container"),
    "hopper": ("railcar", 12.0, 60000, 0.95, 0.0, "freight_wagon"),
}
# name: real counter length (m); the order is the stall variant order.
STALLS = {"lean_to": 3.2, "canopy": 3.0, "table": 2.5, "hand_cart": 2.2}
# name: real length (m) of the hut's long side; the order is the variant
# order. The ruins follow the intact huts as variants of their own.
HUTS = {"guard": 2.6, "cabin": 6.0, "shed": 4.0, "shelter": 3.2, "kiosk": 2.5, "tent": 5.0}
# name: real length (m); the order is the clutter variant order.
CLUTTER = {"drums": 1.24, "pallets": 1.2, "reel": 1.84, "cylinders": 2.0, "cabinet": 1.3, "hydrant": 0.8,
           "sleepers": 2.9, "skid": 2.4, "rubbish": 2.0, "tyres": 1.6, "crates": 1.6, "sacks": 1.4, "tarp": 2.5,
           "washing": 3.0, "genset": 1.6, "haystack": 2.2, "cart": 2.8, "jerrycans": 1.2, "sandbags": 2.6,
           "fuel_pump": 0.9, "air_post": 0.6, "tyre_stack": 1.8, "engine": 1.3}
# name: height (m) above the ground, for the light shadow the game draws
# (PropSpriteLayer.shadow_heights). A ruined hut is HUT_RUIN_HEIGHT of its
# hut's height; a broken stall casts none. Placeholders.
HEIGHTS = {
    "hatchback": 1.45, "sports": 1.25, "estate": 1.5, "suv": 1.75, "pickup": 1.8, "ambulance": 2.6,
    "minibus": 2.4, "fire_engine": 3.0, "container_truck": 4.0, "tanker": 3.5, "dump_truck": 3.2,
    "bus_city": 3.0, "bus_coach": 3.5, "tank_west": 2.4, "tank_east": 2.3, "apc": 2.4,
    "military_truck": 3.0, "container_20ft_a": 2.6, "container_20ft_b": 2.6, "container_40ft": 2.6,
    "metro_cab": 3.6, "metro_car": 3.6, "boxcar": 4.0, "flatcar": 1.3, "flatcar_container": 3.9, "hopper": 3.8,
    "lean_to": 2.2, "canopy": 2.5, "table": 1.0, "hand_cart": 1.2,
    "guard": 2.6, "cabin": 2.7, "shed": 2.4, "shelter": 2.2, "kiosk": 2.5, "tent": 2.2,
    "drums": 0.9, "pallets": 1.0, "reel": 1.5, "cylinders": 0.5, "cabinet": 1.9, "hydrant": 0.8,
    "sleepers": 0.5, "skid": 1.0, "rubbish": 0.6, "tyres": 0.8, "crates": 1.0, "sacks": 0.6, "tarp": 0.8,
    "washing": 1.8, "genset": 1.3, "haystack": 1.8, "cart": 1.0, "jerrycans": 0.5, "sandbags": 0.8,
    "fuel_pump": 1.9, "air_post": 1.2, "tyre_stack": 0.9, "engine": 0.8,
}
HUT_RUIN_HEIGHT = 0.5
FOLIAGE_SIZE = {"tree": 512, "bush": 256}


def body_bounds(a, thresh=0.08):
    ys, xs = np.nonzero(a[..., 3] > thresh)
    return xs.min(), xs.max() + 1, ys.min(), ys.max() + 1


def resize_premultiplied(im, n):
    a = np.asarray(im).astype(np.float32) / 255
    pm = np.concatenate([a[..., :3] * a[..., 3:], a[..., 3:]], -1)
    small = np.asarray(Image.fromarray((pm * 255).astype(np.uint8)).resize((n, n), Image.LANCZOS)).astype(np.float32) / 255
    al = small[..., 3:]
    rgb = np.where(al > 1e-3, small[..., :3] / np.maximum(al, 1e-3), 0)
    return np.concatenate([np.clip(rgb, 0, 1), al], -1)


def save_if_changed(im, path):
    """Writes the image unless the file already holds the same pixels, so
    an unchanged sprite keeps its file (and Godot's import of it)."""
    if os.path.exists(path):
        old = Image.open(path)
        if old.size == im.size and np.array_equal(np.asarray(old.convert(im.mode)), np.asarray(im)):
            return
    im.save(path)


def main(src, project):
    out = os.path.join(project, OUT_DIR)
    os.makedirs(out, exist_ok=True)
    cat = {}
    counts = {}
    for f in sorted(os.listdir(src)):
        if not f.endswith(".png"):
            continue
        im = Image.open(os.path.join(src, f)).convert("RGBA")
        if f.startswith("tree_branches_") or f.startswith("bush_"):
            kind = "tree" if f.startswith("tree") else "bush"
            counts[kind] = counts.get(kind, 0) + 1
            name = f"{kind}_{counts[kind]}.png"
            a = resize_premultiplied(im, FOLIAGE_SIZE[kind])
            save_if_changed(Image.fromarray((a * 255 + 0.5).astype(np.uint8)), os.path.join(out, name))
            x0, x1, y0, y1 = body_bounds(a)
            span = float(np.mean([(x1 - x0) / a.shape[1], (y1 - y0) / a.shape[0]]))
            cat.setdefault(kind, []).append({"file": name, "span": round(span, 3)})
        elif f.startswith("stall_"):
            if f.endswith("_broken.png"):
                continue
            sname = f[len("stall_"):-4]
            broken = f"stall_{sname}_broken.png"
            save_if_changed(im, os.path.join(out, f))
            if os.path.exists(os.path.join(src, broken)):
                save_if_changed(Image.open(os.path.join(src, broken)).convert("RGBA"), os.path.join(out, broken))
            a = np.asarray(im).astype(np.float32) / 255
            x0, x1, y0, y1 = body_bounds(a)
            cat.setdefault("stall", []).append({
                "file": f, "broken": broken, "span": round((x1 - x0) / a.shape[1], 3),
                "length_m": STALLS[sname], "width_m": round(STALLS[sname] * (y1 - y0) / (x1 - x0), 2),
                "height_m": HEIGHTS[sname], "order": list(STALLS).index(sname),
            })
        elif f.startswith("hut_") or f.startswith("clutter_"):
            kind = "hut" if f.startswith("hut_") else "clutter"
            ruin = f.endswith("_broken.png")
            sname = f[len(kind) + 1:-(len("_broken.png") if ruin else 4)]
            table = HUTS if kind == "hut" else CLUTTER
            save_if_changed(im, os.path.join(out, f))
            # A ruin is on its intact hut's canvas and scale, so it takes that hut's span.
            body = Image.open(os.path.join(src, f"hut_{sname}.png")).convert("RGBA") if ruin else im
            a = np.asarray(body).astype(np.float32) / 255
            x0, x1, y0, y1 = body_bounds(a)
            cat.setdefault(kind, []).append({
                "file": f, "span": round((x1 - x0) / a.shape[1], 3),
                "length_m": table[sname], "width_m": round(table[sname] * (y1 - y0) / (x1 - x0), 2),
                "height_m": round(HEIGHTS[sname] * (HUT_RUIN_HEIGHT if ruin else 1.0), 2), "ruin": ruin, "order": list(table).index(sname) + (len(table) if ruin else 0),
            })
        elif f.startswith("vehicle_"):
            vname = f[len("vehicle_"):-4]
            kind, length, mass, block, weight, source = VEHICLES[vname]
            turned = im.rotate(-90, expand=True)
            name = f"vehicle_{vname}.png"
            save_if_changed(turned, os.path.join(out, name))
            a = np.asarray(turned).astype(np.float32) / 255
            x0, x1, y0, y1 = body_bounds(a)
            body_len = x1 - x0
            # Median width along the length, so wing mirrors don't count.
            body_wid = float(np.median((a[:, x0:x1, 3] > 0.08).sum(0)))
            cat.setdefault(kind, []).append({
                "file": name, "span": round(body_len / a.shape[1], 3),
                "length_m": length, "width_m": round(float(length * body_wid / body_len), 2),
                "height_m": HEIGHTS[vname], "mass_kg": mass, "shot_block": block, "weight": weight, "source": source,
            })
    for kind in ("stall", "hut", "clutter"):
        if kind in cat:
            cat[kind].sort(key=lambda e: e.pop("order"))
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sprite_catalogue.json"), "w", encoding="utf-8") as fh:
        json.dump(cat, fh, indent=1)
    return cat


if __name__ == "__main__":
    for k, v in main(sys.argv[1], sys.argv[2]).items():
        print(k, [(e["file"], e.get("length_m"), e.get("width_m")) for e in v])
