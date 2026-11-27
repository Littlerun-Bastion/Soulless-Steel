"""Renders a window of a generator run to a PNG, to look at the map without
Godot. It draws the work dir's mesh files (all seven sublayers, in the game's
order) with their vertex greys, the props as their sprites, and, with
--annotate, the salvage sources (yellow boxes), the obstacles (red outlines)
and the ruin state of each building (a coloured dot: green damaged, orange
gutted, red collapsed). The game's grain shaders and lighting are not drawn.

Usage: python render_preview.py <work dir> <project> <out.png>
                                 --window x0,y0,x1,y1 [--scale px_per_m]
                                 [--annotate] [--no-props] [--districts]
                                 [--camera x,y | --flat]

The window is in map-frame metres (origin at the map centre, y down).
Talls lean away from the window's centre, as the game leans them from the
screen's centre; --camera x,y leans them from another point, --flat draws
them standing in place.
--districts draws the district grid of the whole map instead (one pixel per
cell, coloured), with the play area's edge.
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

PX_PER_M = 20.0
DRAW_ORDER = ("ground", "groundlines", "halos", "interiors", "PROPS", "roofs", "FOLIAGE", "overheads", "talls")
# Eye height (metres) of the talls shift; the game's talls shader uses the
# same rule, shift = (vertex - camera) * h / (EYE_M - h), with h clamped to
# MAX_H_M (TallsLean.EYE_M, MAX_HEIGHT_M).
EYE_M = 150.0
MAX_H_M = 100.0
GROUND_GREY = 0.16
DISTRICT_COLOURS = {0: (120, 120, 120), 1: (200, 90, 40), 2: (220, 190, 40), 3: (90, 160, 70)}
STATE_COLOURS = {1: (80, 220, 80), 2: (255, 150, 30), 3: (240, 40, 40)}
SALVAGE_COLOUR = (255, 230, 60)
OBSTACLE_COLOUR = (255, 60, 60)


def read_mesh(path, camera=None, eye=EYE_M):
    """Vertices (world px), grey/alpha and indices of one mesh file. Talls
    vertices are shifted away from camera (world px) by their height, as the
    game's talls shader does with eye metres for its eye height; with no
    camera they stay where they stand."""
    with open(path, "rb") as fh:
        n, ni, flag = struct.unpack("<iii", fh.read(12))
        xy = np.frombuffer(fh.read(n * 8), np.float32).reshape(n, 2)
        ga = np.frombuffer(fh.read(n * 2), np.uint8).reshape(n, 2).astype(np.float32) / 255
        if flag == 1:
            fh.read(n * 8)
        elif flag == 2:
            h = np.clip(np.frombuffer(fh.read(n * 4), np.float32), 0.0, MAX_H_M)
            if camera is not None:
                k = h / np.maximum(eye - h, 1.0)
                xy = xy + (xy - np.asarray(camera, np.float32)) * k[:, None]
        idx = np.frombuffer(fh.read(ni * 4), np.uint32)
    return xy, ga, idx


class Canvas:
    def __init__(self, window, scale):
        self.x0, self.y0, self.x1, self.y1 = window
        self.scale = scale
        self.w = int(round((self.x1 - self.x0) * scale))
        self.h = int(round((self.y1 - self.y0) * scale))
        self.img = np.full((self.h, self.w), GROUND_GREY, np.float32)

    def to_px(self, xy_m):
        return np.stack([(xy_m[:, 0] - self.x0) * self.scale, (xy_m[:, 1] - self.y0) * self.scale], 1)

    def triangles(self, pts, grey, alpha):
        """pts (n, 3, 2) in canvas px; grey, alpha (n, 3). Each triangle is
        blended in order with its colours interpolated over it."""
        lo = np.floor(pts.min(1)).astype(int)
        hi = np.ceil(pts.max(1)).astype(int)
        vis = (hi[:, 0] >= 0) & (hi[:, 1] >= 0) & (lo[:, 0] < self.w) & (lo[:, 1] < self.h)
        img = self.img
        for t in np.flatnonzero(vis):
            (ax, ay), (bx, by), (cx, cy) = pts[t]
            x0, y0 = max(lo[t, 0], 0), max(lo[t, 1], 0)
            x1, y1 = min(hi[t, 0], self.w - 1), min(hi[t, 1], self.h - 1)
            if x1 < x0 or y1 < y0:
                continue
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(det) < 1e-9:
                continue
            xs = np.arange(x0, x1 + 1) + 0.5
            ys = np.arange(y0, y1 + 1) + 0.5
            px, py = np.meshgrid(xs, ys)
            l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / det
            l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / det
            l3 = 1 - l1 - l2
            inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
            if not inside.any():
                continue
            g = grey[t, 0] * l1 + grey[t, 1] * l2 + grey[t, 2] * l3
            a = (alpha[t, 0] * l1 + alpha[t, 1] * l2 + alpha[t, 2] * l3) * inside
            sl = img[y0:y1 + 1, x0:x1 + 1]
            sl += (g - sl) * a

    def paste(self, sprite, x_m, y_m, rot, length_m, span, tone=1.0):
        """A sprite facing +x, its drawn body length_m long."""
        w_px = length_m / max(span, 1e-3) * self.scale
        if w_px < 2:
            return
        k = w_px / sprite.width
        im = sprite.resize((max(1, int(sprite.width * k)), max(1, int(sprite.height * k))), Image.BILINEAR)
        im = im.rotate(-np.degrees(rot), expand=True, resample=Image.BILINEAR)
        a = np.asarray(im).astype(np.float32) / 255
        lum = (a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)) * tone
        al = a[..., 3]
        cx, cy = (x_m - self.x0) * self.scale, (y_m - self.y0) * self.scale
        ox, oy = int(round(cx - im.width / 2)), int(round(cy - im.height / 2))
        xa, ya = max(ox, 0), max(oy, 0)
        xb, yb = min(ox + im.width, self.w), min(oy + im.height, self.h)
        if xb <= xa or yb <= ya:
            return
        sl = self.img[ya:yb, xa:xb]
        sa = al[ya - oy:yb - oy, xa - ox:xb - ox]
        sl += (lum[ya - oy:yb - oy, xa - ox:xb - ox] - sl) * sa


def load_sprites(project, catalogue):
    out = {}
    d = os.path.join(project, "assets", "images", "map", "props")
    for kind, entries in catalogue.items():
        out[kind] = []
        for e in entries:
            p = os.path.join(d, e["file"])
            out[kind].append(Image.open(p).convert("RGBA") if os.path.exists(p) else None)
    return out


def draw_layer(cv, work, manifest, sub, camera=None):
    x0, y0, x1, y1 = (v * PX_PER_M for v in (cv.x0, cv.y0, cv.x1, cv.y1))
    for name, (bx, by, bw, bh) in sorted(manifest.items()):
        if name.rsplit("_", 2)[0] != sub:
            continue
        if bx > x1 or by > y1 or bx + bw < x0 or by + bh < y0:
            continue
        xy, ga, idx = read_mesh(os.path.join(work, name + ".bin"), camera)
        tri = idx.reshape(-1, 3)
        pts = cv.to_px(xy / PX_PER_M)[tri]
        cv.triangles(pts, ga[tri, 0], ga[tri, 1])


def draw_props(cv, props, catalogue, sprites, kinds):
    sprite_kind = {"vehicle_wreck": "vehicle"}
    tones = {"vehicle_wreck": 0.55, "tree": 0.85, "bush": 0.6}
    k_names = props["kinds"]
    for it in props["items"]:
        kind = k_names[it[0]]
        if kind not in kinds:
            continue
        x, y = it[1] / PX_PER_M, it[2] / PX_PER_M
        if x < cv.x0 - 20 or x > cv.x1 + 20 or y < cv.y0 - 20 or y > cv.y1 + 20:
            continue
        sk = sprite_kind.get(kind, kind)
        ent = catalogue.get(sk, [])
        if not ent:
            continue
        v = it[6] if len(it) > 6 and 0 <= it[6] < len(ent) else int(abs(hash((round(x, 1), round(y, 1))))) % len(ent)
        spr = sprites[sk][v]
        if spr is None:
            continue
        cv.paste(spr, x, y, it[3], it[4] / PX_PER_M, ent[v]["span"], tones.get(kind, 1.0))


def annotate(img, cv, work):
    d = ImageDraw.Draw(img)
    s = cv.scale

    def tp(x, y):
        return ((x - cv.x0) * s, (y - cv.y0) * s)

    path = os.path.join(work, "obstacles.bin")
    if os.path.exists(path):
        with open(path, "rb") as fh:
            n = struct.unpack("<i", fh.read(4))[0]
            for _ in range(n):
                kind, k = struct.unpack("<ii", fh.read(8))
                pts = np.frombuffer(fh.read(k * 8), np.float32).reshape(k, 2) / PX_PER_M
                if pts[:, 0].max() < cv.x0 or pts[:, 0].min() > cv.x1 or pts[:, 1].max() < cv.y0 or pts[:, 1].min() > cv.y1:
                    continue
                d.line([tp(*p) for p in pts] + [tp(*pts[0])], fill=OBSTACLE_COLOUR, width=1)
    path = os.path.join(work, "footprints.bin")
    if os.path.exists(path):
        with open(path, "rb") as fh:
            n = struct.unpack("<i", fh.read(4))[0]
            cents = []
            for _ in range(n):
                k = struct.unpack("<i", fh.read(4))[0]
                pts = np.frombuffer(fh.read(k * 8), np.float32).reshape(k, 2) / PX_PER_M
                cents.append(pts.mean(0))
            rest = fh.read()
            states = np.frombuffer(rest[:n], np.uint8) if len(rest) >= 2 * n else np.zeros(n, np.uint8)
        for (x, y), st in zip(cents, states):
            if st and cv.x0 <= x <= cv.x1 and cv.y0 <= y <= cv.y1:
                px, py = tp(x, y)
                d.ellipse([px - 3, py - 3, px + 3, py + 3], fill=STATE_COLOURS[int(st)])
    path = os.path.join(work, "salvage.json")
    if os.path.exists(path):
        data = json.load(open(path, encoding="utf-8"))
        for it in data["items"]:
            x, y, rot, w, h = it[1] / PX_PER_M, it[2] / PX_PER_M, it[3], it[4] / PX_PER_M, it[5] / PX_PER_M
            if not (cv.x0 - 10 <= x <= cv.x1 + 10 and cv.y0 - 10 <= y <= cv.y1 + 10):
                continue
            c, sn = np.cos(rot), np.sin(rot)
            corners = [(x + c * dx - sn * dy, y + sn * dx + c * dy) for dx, dy in
                       ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2))]
            d.line([tp(*p) for p in corners] + [tp(*corners[0])], fill=SALVAGE_COLOUR, width=1)
            if s >= 3:
                d.text(tp(x + w / 2 + 0.5, y - h / 2), data["kinds"][it[0]], fill=SALVAGE_COLOUR)


def render(work, project, out, window, scale=4.0, show_props=True, notes=False, camera="centre"):
    """camera: where the talls lean away from, in map metres; "centre" is the
    window's centre (as the game leans them from the screen's centre), None
    draws them standing flat."""
    manifest = json.load(open(os.path.join(work, "manifest.json"), encoding="utf-8"))
    if camera == "centre":
        camera = ((window[0] + window[2]) / 2, (window[1] + window[3]) / 2)
    cam_px = None if camera is None else (camera[0] * PX_PER_M, camera[1] * PX_PER_M)
    cat_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sprite_catalogue.json")
    catalogue = json.load(open(cat_path, encoding="utf-8"))
    sprites = load_sprites(project, catalogue)
    props = json.load(open(os.path.join(work, "props.json"), encoding="utf-8")) if show_props else None
    cv = Canvas(window, scale)
    for sub in DRAW_ORDER:
        if sub == "PROPS":
            if props:
                draw_props(cv, props, catalogue, sprites, ("vehicle_wreck", "vehicle", "truck", "bus", "military",
                                                           "container", "stall", "debris", "clutter", "hut",
                                                           "railcar"))
            continue
        if sub == "FOLIAGE":
            if props:
                draw_props(cv, props, catalogue, sprites, ("bush", "tree"))
            continue
        draw_layer(cv, work, manifest, sub, cam_px if sub == "talls" else None)
    grey = (np.clip(cv.img, 0, 1) * 255).astype(np.uint8)
    img = Image.fromarray(grey).convert("RGB")
    if notes:
        annotate(img, cv, work)
    img.save(out)
    return out


def render_districts(work, out, play_half_m=2500.0):
    with open(os.path.join(work, "districts.bin"), "rb") as fh:
        w, h, ox, oy, cell = struct.unpack("<iifff", fh.read(20))
        codes = np.frombuffer(fh.read(w * h), np.uint8).reshape(h, w)
    rgb = np.zeros((h, w, 3), np.uint8)
    for c, col in DISTRICT_COLOURS.items():
        rgb[codes == c] = col
    k = 4
    img = Image.fromarray(rgb).resize((w * k, h * k), Image.NEAREST)
    d = ImageDraw.Draw(img)
    half = -ox / PX_PER_M
    cell_m = cell / PX_PER_M
    e0 = (half - play_half_m) / cell_m * k
    e1 = (half + play_half_m) / cell_m * k
    d.rectangle([e0, e0, e1, e1], outline=(255, 255, 255), width=2)
    for i, (c, name) in enumerate(((0, "residential"), (1, "industrial"), (2, "market"), (3, "farmland"))):
        d.rectangle([10, 10 + i * 18, 24, 24 + i * 18], fill=DISTRICT_COLOURS[c])
        d.text((30, 11 + i * 18), name, fill=(255, 255, 255))
    img.save(out)
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    opts = {"--scale": 4.0}
    win = None
    if "--window" in args:
        i = args.index("--window")
        win = tuple(float(v) for v in args[i + 1].split(","))
        del args[i:i + 2]
    if "--scale" in args:
        i = args.index("--scale")
        opts["--scale"] = float(args[i + 1])
        del args[i:i + 2]
    cam = "centre"
    if "--camera" in args:
        i = args.index("--camera")
        cam = tuple(float(v) for v in args[i + 1].split(","))
        del args[i:i + 2]
    flags = {a for a in args if a.startswith("--")}
    args = [a for a in args if not a.startswith("--")]
    if "--flat" in flags:
        cam = None
    if "--districts" in flags:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from frame import PLAY_HALF_M
        print(render_districts(args[0], args[2], PLAY_HALF_M))
    else:
        print(render(args[0], args[1], args[2], win, opts["--scale"], "--no-props" not in flags, "--annotate" in flags,
                     cam))
