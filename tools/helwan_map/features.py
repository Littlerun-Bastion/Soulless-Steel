"""Per-pixel features of the reference image, on the map's image grid
(grid_n pixels across the map, about 2 m per pixel).

mk     greyscale image, 0..1 (through grey_map, if set)
tex    local roughness: dense housing reads as fine light/dark texture
       (through texture_map, if set)
dens   OSM street density
water  dark areas near OSM water, plus OSM water that is dark in the image

The zone, ground and prop rules use fixed thresholds on mk and tex, tuned on
the first Helwan mockup. grey_map and texture_map (from calibrate_image.py)
bring another image's values to that scale.
"""
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

from frame import CONFIG, FIT_SPAN_M, MAP_M, MOCK_N, SCALE, image_path, m_to_world, world_to_mock


def image_grid(path=None):
    """The reference image as greyscale 0..1, resampled to the map's grid."""
    img = np.asarray(Image.open(path or image_path()).convert("RGB")).astype(np.float32) / 255
    grey = img @ np.array([0.299, 0.587, 0.114], np.float32)
    h, w = grey.shape
    n = MOCK_N
    # Grid cell centres in map metres, then in image pixels.
    c = (np.arange(n) + 0.5) / n * MAP_M - MAP_M / 2
    gx = c / SCALE * w / FIT_SPAN_M + w / 2 - 0.5
    gy = c / SCALE * h / FIT_SPAN_M + h / 2 - 0.5
    yy, xx = np.meshgrid(gy, gx, indexing="ij")
    return ndi.map_coordinates(grey, [yy, xx], order=1, mode="nearest")


def texture(mk):
    hp = mk - ndi.gaussian_filter(mk, 2.5)
    return np.sqrt(ndi.gaussian_filter(hp ** 2, 5))


def apply_map(values, pairs):
    if not pairs:
        return values
    p = np.asarray(pairs, float)
    return np.interp(values, p[:, 0], p[:, 1])


def compute(feats):
    mk = apply_map(image_grid(), CONFIG.get("grey_map"))
    n = MOCK_N
    osmw = Image.new("L", (n, n))
    dw = ImageDraw.Draw(osmw)
    rd = Image.new("L", (n, n))
    dr = ImageDraw.Draw(rd)
    for kind, rings, p in feats:
        if kind == "poly" and p.get("natural") == "water":
            for i, r in enumerate(rings):
                dw.polygon([tuple(q) for q in world_to_mock(m_to_world(r))], fill=0 if i else 255)
        if kind == "line" and "highway" in p:
            dr.line([tuple(q) for q in world_to_mock(m_to_world(rings[0]))], fill=255, width=1)
    osmw = np.asarray(osmw) > 0
    rd = np.asarray(rd) > 0

    tex = apply_map(texture(mk), CONFIG.get("texture_map"))
    dens = ndi.gaussian_filter(rd.astype(float), 12)
    dark = ndi.uniform_filter(mk, 7) < 0.04
    water = ndi.binary_opening(dark, iterations=2) & ndi.binary_dilation(osmw, iterations=12)
    water |= osmw & (ndi.uniform_filter(mk, 5) < 0.07)
    water = ndi.binary_closing(water, iterations=2)
    return dict(mk=mk, tex=tex, dens=dens, water=water)
