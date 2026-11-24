"""Classifies the reference image into zones on the image grid (about 2 m
per pixel).

0 open ground, 1 dense housing, 2 large roof (bright blob), 3 water.
Large roofs also come back as rotated rectangles in grid pixels.

Thresholds can be set per map in inputs/map.json under "zones" (defaults in
DEFAULTS, tuned on the first Helwan mockup):
  housing_tex       texture above this, with streets, is housing
  housing_dens      OSM street density needed for housing
  housing_max_grey  also housing: local brightness (18 m mean) below this,
                    where OSM street density is above housing_grey_dens (for
                    soft images that lose the fine texture); null to turn off
  housing_grey_dens street density needed for the brightness rule
  housing_bright    local brightness above this is never housing (bare sand
                    and rock); null to turn off
  roof_grey         brightness a large roof must be above
  roof_contrast     how much brighter a roof's rim is than the ground round it
  roof_dens         OSM street density a roof needs round it (keeps bare lots
                    in open ground from becoming roofs); 0 to turn off
  roof_max_px       largest blob (grid pixels) taken as one roof
  roof_min_side     narrowest roof (grid pixels)
  roof_max_aspect   longest roof for its width (long thin bright blobs are
                    usually roads)
"""
import numpy as np
import cv2
from scipy import ndimage as ndi

from frame import CONFIG

OPEN, HOUSING, ROOF, WATER = 0, 1, 2, 3

DEFAULTS = {
    "housing_tex": 0.036,
    "housing_dens": 0.012,
    "housing_max_grey": None,
    "housing_grey_dens": 0.012,
    "housing_bright": None,
    "roof_grey": 0.215,
    "roof_contrast": 0.07,
    "roof_dens": 0.0,
    "roof_max_px": 10 ** 9,
    "roof_min_side": 4,
    "roof_max_aspect": 1000.0,
}


def settings():
    out = dict(DEFAULTS)
    out.update(CONFIG.get("zones", {}))
    return out


def classify(f):
    z = settings()
    mk, tex, dens, water = f["mk"], f["tex"], f["dens"], f["water"]
    housing = (tex > z["housing_tex"])
    if z["housing_max_grey"] is not None:
        housing |= (ndi.uniform_filter(mk, 9) < z["housing_max_grey"]) & (dens > z["housing_grey_dens"])
    housing &= (dens > z["housing_dens"]) & ~water
    if z["housing_bright"] is not None:
        housing &= ndi.uniform_filter(mk, 9) < z["housing_bright"]
    housing = ndi.binary_closing(housing, iterations=3)
    housing = ndi.binary_opening(housing, iterations=2)
    lab, n = ndi.label(housing)
    sizes = ndi.sum(housing, lab, range(1, n + 1))
    housing = np.isin(lab, 1 + np.flatnonzero(sizes >= 150))

    sm = ndi.gaussian_filter(mk, 0.8)
    bright = (sm > z["roof_grey"]) & ~water
    bright = ndi.binary_opening(bright, iterations=1)
    lab, n = ndi.label(bright)
    rects = []
    roof = np.zeros_like(bright)
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        comp = lab[sl] == i
        area = comp.sum()
        if area < 30 or area > z["roof_max_px"]:
            continue
        if z["roof_dens"] > 0 and dens[sl][comp].mean() < z["roof_dens"]:
            continue
        ys, xs = np.nonzero(comp)
        pts = np.stack([xs + sl[1].start, ys + sl[0].start], 1).astype(np.float32)
        (cx, cy), (w, h), ang = cv2.minAreaRect(pts)
        fill = area / max(1.0, w * h)
        if fill < 0.55 or min(w, h) < z["roof_min_side"] or max(w, h) > z["roof_max_aspect"] * min(w, h):
            continue
        # Roofs have a hard edge; dust and bare ground fade out. Compare the
        # blob's rim with a thin ring just outside it.
        pad = 4
        y0, x0 = max(0, sl[0].start - pad), max(0, sl[1].start - pad)
        y1, x1 = sl[0].stop + pad, sl[1].stop + pad
        full = np.zeros(mk[y0:y1, x0:x1].shape, bool)
        full[sl[0].start - y0:sl[0].stop - y0, sl[1].start - x0:sl[1].stop - x0] = comp
        rim = full & ~ndi.binary_erosion(full, iterations=2)
        ring = ndi.binary_dilation(full, iterations=3) & ~ndi.binary_dilation(full, iterations=1)
        win = mk[y0:y1, x0:x1]
        contrast = win[rim].mean() - win[ring].mean()
        if contrast < z["roof_contrast"]:
            continue
        rects.append(((cx + 0.5, cy + 0.5), (w + 1, h + 1), ang, float(mk[sl][comp].mean())))
        roof[sl] |= comp
    zone = np.full(mk.shape, OPEN, np.uint8)
    zone[housing] = HOUSING
    zone[roof] = ROOF
    zone[water] = WATER
    return zone, rects
