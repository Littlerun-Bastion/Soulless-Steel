"""Finds where the reference image sits on the OSM data: its centre, span and
rotation. Prints the result and, with --write, puts it into inputs/map.json
(image_centre_m, image_span_m, image_rot_deg).

Usage:
  python fit_image.py [--span-guess 5000] [--write]

It draws the OSM streets, rail and water as an image and slides the
reference image over it at a range of spans and rotations, scoring how well
the image's thin light or dark lines match the streets and its darkest areas
match the water. A coarse search (12 m per pixel, spans from 0.8 to 1.2 times
the guess) is refined at 4 m per pixel. Check the result by eye: it writes
fit_overlay.png (the streets drawn over the image) next to this script.

Water carries most of the score where a river runs along one edge, and fixes
only one direction well; the streets fix the rest, so give the image some
road network all the way to its edges.
"""
import argparse
import json
import os

import cv2
import numpy as np
from scipy import ndimage as ndi

import frame
import geo

SKIP_HIGHWAYS = {"footway", "path", "steps", "pedestrian", "track", "cycleway", "service"}
SEARCH_HALF_M = 15000.0


def _osm_raster(feats, res):
    n = int(2 * SEARCH_HALF_M / res)
    road = np.zeros((n, n), np.uint8)
    water = np.zeros((n, n), np.uint8)

    def px(r):
        return np.int32(((np.asarray(r) + SEARCH_HALF_M) / res).round())

    for kind, rings, p in feats:
        if kind == "line" and ("highway" in p and p["highway"] not in SKIP_HIGHWAYS or p.get("railway") == "rail"):
            cv2.polylines(road, [px(rings[0])], False, 255, 1)
        elif kind == "poly" and (p.get("natural") == "water" or "water" in p or "waterway" in p):
            cv2.fillPoly(water, [px(rings[0])], 255)
            for r in rings[1:]:
                cv2.fillPoly(water, [px(r)], 0)
    road = ndi.gaussian_filter(road.astype(np.float32) / 255, 1.2)
    return road, water.astype(np.float32) / 255


def _search(feats, grey, res, spans, rots):
    road, water = _osm_raster(feats, res)
    h, w = grey.shape
    best = None
    for span in spans:
        n = int(round(span / res))
        for rot in rots:
            m = cv2.getRotationMatrix2D((w / 2, h / 2), rot, n / w)
            m[:, 2] += (n - w) / 2, (n - h) / 2
            g = cv2.warpAffine(grey, m, (n, n), flags=cv2.INTER_AREA, borderValue=float(grey.mean()))
            lines = ndi.gaussian_filter(np.abs(g - ndi.gaussian_filter(g, 3.0)), 1.2)
            dark = (ndi.gaussian_filter(g, 2) < np.percentile(g, 6)).astype(np.float32)
            a = cv2.matchTemplate(road, lines, cv2.TM_CCOEFF_NORMED)
            b = cv2.matchTemplate(water, dark, cv2.TM_CCOEFF_NORMED)
            # Windows with almost no roads, or all or no water, score noise.
            dens = cv2.boxFilter(road, -1, (n, n), anchor=(0, 0))[:a.shape[0], :a.shape[1]]
            wet = cv2.boxFilter(water, -1, (n, n), anchor=(0, 0))[:b.shape[0], :b.shape[1]]
            a = np.nan_to_num(np.where(dens > road.mean() * 0.25 + 0.01, a, -1.0), nan=-1.0, posinf=-1.0, neginf=-1.0)
            b = np.nan_to_num(np.where((wet > 0.01) & (wet < 0.6), b, 0.0), nan=0.0, posinf=0.0, neginf=0.0)
            score = a + 0.5 * b
            _, top, _, loc = cv2.minMaxLoc(score)
            if best is None or top > best[0]:
                cx = (loc[0] + n / 2) * res - SEARCH_HALF_M
                cy = (loc[1] + n / 2) * res - SEARCH_HALF_M
                best = (top, float(span), float(rot), cx, cy)
        print("  span %5.0f m: best so far span %.0f, rotation %.1f, centre %.0f, %.0f (score %.3f)"
              % (span, best[1], best[2], best[3], best[4], best[0]), flush=True)
    return best


def _overlay(feats, img, span, rot, cx, cy, path):
    h, w = img.shape[:2]
    res = span / w
    c, s = np.cos(np.radians(rot)), np.sin(np.radians(rot))
    out = img.copy()
    for kind, rings, p in feats:
        if kind == "line" and ("highway" in p or "railway" in p):
            q = np.asarray(rings[0]) - (cx, cy)
            u, v = c * q[:, 0] + s * q[:, 1], -s * q[:, 0] + c * q[:, 1]
            pts = np.int32(np.stack([u / res + w / 2, v / res + h / 2], 1).round())
            cv2.polylines(out, [pts], False, (0, 0, 255), 1, cv2.LINE_AA)
    cv2.imwrite(path, out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--span-guess", type=float, default=float(frame.CONFIG.get("image_span_m", 5000)))
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    feats = geo.load(os.path.join(frame.HERE, "inputs", "osm.geojson"))
    img = cv2.imread(frame.image_path())
    grey = img.astype(np.float32).mean(2) / 255
    g = args.span_guess
    print("coarse search")
    _, span, rot, _, _ = _search(feats, grey, 12.0, np.arange(0.8 * g, 1.21 * g, 0.04 * g), np.arange(-4.0, 4.1, 2.0))
    print("fine search")
    score, span, rot, cx, cy = _search(feats, grey, 4.0, np.arange(span - 150, span + 151, 50), np.arange(rot - 1.5, rot + 1.6, 0.5))
    print("fit: image_span_m %.0f, image_rot_deg %.1f, image_centre_m [%.0f, %.0f] (score %.3f)" % (span, rot, cx, cy, score))
    _overlay(feats, img, span, rot, cx, cy, os.path.join(frame.HERE, "fit_overlay.png"))
    if args.write:
        path = os.path.join(frame.HERE, "inputs", "map.json")
        cfg = json.load(open(path, encoding="utf-8"))
        cfg.update(image_span_m=round(span), image_rot_deg=round(rot, 1), image_centre_m=[round(cx), round(cy)])
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh, indent=2)
        print("wrote", path)


if __name__ == "__main__":
    main()
