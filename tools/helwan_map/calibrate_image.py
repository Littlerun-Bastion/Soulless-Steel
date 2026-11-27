"""Calibrates a new reference image against the one the zone rules were tuned
on, and writes grey_map and texture_map into inputs/map.json.

Usage:
  python calibrate_image.py <reference image> <span m> <centre x m> <centre y m> <rotation deg>

The reference is the first Helwan mockup (inputs/mockup_2500m.png, 2485 m
across, centred at -81, -94 m, turned 1 degree). Both images are sampled at
the same real-world points where they overlap. grey_map is the quantile map
that gives the new image's brightness the reference's distribution;
texture_map does the same for the texture measure (features.texture), worked
out on each image's own ~2 m grid. Both maps are monotonic, so they keep the
order of values and only change their scale.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

import features
import frame

QUANTILES = np.linspace(0.0, 100.0, 101)


def _ref_pixels(pts_m, n, span, cx, cy, rot):
    c, s = np.cos(np.radians(rot)), np.sin(np.radians(rot))
    x, y = pts_m[:, 0] - cx, pts_m[:, 1] - cy
    u, v = c * x + s * y, -s * x + c * y
    return u / span * n + n / 2 - 0.5, v / span * n + n / 2 - 0.5


def _quantile_map(src, dst):
    a = np.percentile(src, QUANTILES)
    b = np.percentile(dst, QUANTILES)
    keep = np.concatenate([[True], np.diff(a) > 1e-6])
    return [[round(float(p), 6), round(float(q), 6)] for p, q in zip(a[keep], b[keep])]


def main(ref_path, span, cx, cy, rot):
    ref = np.asarray(Image.open(ref_path).convert("L")).astype(float) / 255
    rn = ref.shape[0]
    new_grey = features.image_grid()
    n = new_grey.shape[0]
    # Real-world metres of every new grid cell, kept where the reference has it.
    c = (np.arange(n) + 0.5) / n * frame.MAP_M - frame.MAP_M / 2
    yy, xx = np.meshgrid(c, c, indexing="ij")
    world_m = np.stack([xx.ravel(), yy.ravel()], 1)
    # Invert frame.m_to_world: world metres -> real metres.
    u, v = world_m[:, 0] / frame.SCALE, world_m[:, 1] / frame.SCALE
    cr, sr = np.cos(np.radians(frame.FIT_ROT_DEG)), np.sin(np.radians(frame.FIT_ROT_DEG))
    real = np.stack([cr * u - sr * v + frame.FIT_CX, sr * u + cr * v + frame.FIT_CY], 1)
    px, py = _ref_pixels(real, rn, span, cx, cy, rot)
    inside = (px >= 2) & (px < rn - 3) & (py >= 2) & (py < rn - 3)
    if inside.mean() < 0.02:
        sys.exit("the images barely overlap; check the fit")
    ref_tex = features.texture(ref)
    ref_grey_s = ndi.map_coordinates(ref, [py[inside], px[inside]], order=1)
    ref_tex_s = ndi.map_coordinates(ref_tex, [py[inside], px[inside]], order=1)
    grey_map = _quantile_map(new_grey.ravel()[inside], ref_grey_s)
    new_tex = features.texture(features.apply_map(new_grey, grey_map))
    texture_map = _quantile_map(new_tex.ravel()[inside], ref_tex_s)
    cfg_path = os.path.join(frame.HERE, "inputs", "map.json")
    cfg = json.load(open(cfg_path, encoding="utf-8"))
    cfg["grey_map"] = grey_map
    cfg["texture_map"] = texture_map
    with open(cfg_path, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2)
    print("overlap %.0f%% of the map; wrote grey_map (%d points), texture_map (%d points)"
          % (100 * inside.mean(), len(grey_map), len(texture_map)))


if __name__ == "__main__":
    main(sys.argv[1], *(float(v) for v in sys.argv[2:6]))
