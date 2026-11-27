"""Builds the Helwan map's macro tone texture and ground mask.

macro_tone.png  1024 greyscale. The mockup blurred until no building edges are
                left, scaled so its average is 0.5. The shader multiplies the
                ground by twice this value, so the map keeps its average.
ground_mask.png 2048 RGB. R snow, G sand, B dirt & rocks; cracked earth is the
                remainder. Each texel covers about 1.2 m.
"""
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

from zones import HOUSING, OPEN, ROOF

MACRO_SIZE = 1024
MASK_SIZE = 2048
MACRO_BLUR_M = 10.0
# Wind from the north-west piles snow up on the south-east side of buildings.
LEE_DIR = np.array([1.0, 1.0]) / np.sqrt(2.0)


def fbm(n, seed, octaves):
    """Smooth noise in 0..1: summed blurred white noise, sigma in texels."""
    rng = np.random.default_rng(seed)
    out = np.zeros((n, n))
    total = 0.0
    for sigma, amp in octaves:
        layer = ndi.gaussian_filter(rng.standard_normal((n, n)), sigma, mode="wrap")
        out += layer / layer.std() * amp
        total += amp
    out /= total
    return np.clip(0.5 + out * 0.25, 0, 1)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def resize(a, n, order=1):
    return ndi.zoom(a, n / a.shape[0], order=order, mode="nearest")


def macro_tone(f, half_m):
    mk = f["mk"]
    sigma_px = MACRO_BLUR_M / (2 * half_m / mk.shape[0])
    t = ndi.gaussian_filter(mk, sigma_px)
    t = resize(t, MACRO_SIZE)
    t = 0.5 * t / t.mean()
    return np.clip(t, 0, 1)


def building_raster(buildings, half_m, n):
    im = Image.new("L", (n, n))
    d = ImageDraw.Draw(im)
    k = n / (2 * half_m)
    for b, _, _ in buildings:
        for g in getattr(b, "geoms", [b]):
            if g.geom_type != "Polygon":
                continue
            pts = [((x + half_m) * k, (y + half_m) * k) for x, y in g.exterior.coords]
            if len(pts) > 2:
                d.polygon(pts, fill=255)
    return np.asarray(im).astype(float) / 255


def ground_mask(f, zone, buildings, half_m):
    n = MASK_SIZE
    mk = f["mk"]
    lum = resize(ndi.gaussian_filter(mk, 2.0), n)
    tex = resize(f["tex"], n)
    z = resize(zone, n, order=0)
    housing = ndi.gaussian_filter((z == HOUSING).astype(float), 6)
    open_ = ndi.gaussian_filter((z == OPEN).astype(float), 6)

    # Small-scale wobble so class edges don't follow the mockup's 2 m pixels.
    wob = fbm(n, 3, ((3, 1.0), (10, 0.6))) - 0.5
    lum = lum + wob * 0.03

    sand = smoothstep(0.165, 0.215, lum) * (1 - housing)
    sand *= smoothstep(0.035, 0.02, tex + wob * 0.01)
    dirt_open = smoothstep(0.022, 0.04, tex + wob * 0.01) * open_
    dirt = np.clip(dirt_open + housing * 0.55 + wob * 0.4, 0, 1) * (1 - sand)

    texel_m = 2 * half_m / n
    b = building_raster(buildings, half_m, n)
    lee = np.zeros_like(b)
    for step_m in np.arange(1.0, 9.0, 1.0):
        sh = LEE_DIR * step_m / texel_m
        lee = np.maximum(lee, ndi.shift(b, (sh[1], sh[0]), order=0) * (1 - step_m / 9.0))
    lee = ndi.gaussian_filter(lee * (1 - b), 1.5)
    drifts = smoothstep(0.56, 0.68, fbm(n, 11, ((40, 1.0), (14, 0.5), (4, 0.2))))
    snow = np.clip(drifts * 0.9 + lee * 1.1, 0, 1)

    mask = np.stack([snow, sand, dirt], -1)
    return (np.clip(mask, 0, 1) * 255).astype(np.uint8)
