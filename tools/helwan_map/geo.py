"""Loads the OSM GeoJSON and projects it to local metres around a centre point."""
import json, math
import numpy as np

from frame import CONFIG

LAT0, LON0 = (float(v) for v in CONFIG["geo_centre"])
M_LAT = 111132.954 - 559.822 * math.cos(2 * math.radians(LAT0))
M_LON = 111412.84 * math.cos(math.radians(LAT0)) - 93.5 * math.cos(3 * math.radians(LAT0))


def to_m(coords):
    a = np.asarray(coords, float)
    return np.stack([(a[:, 0] - LON0) * M_LON, -(a[:, 1] - LAT0) * M_LAT], 1)


def load(path):
    feats = json.load(open(path, encoding="utf-8"))["features"]
    out = []
    for f in feats:
        g = f["geometry"]
        if g["type"] == "LineString":
            parts = [("line", [to_m(g["coordinates"])])]
        elif g["type"] == "Polygon":
            parts = [("poly", [to_m(r) for r in g["coordinates"]])]
        elif g["type"] == "MultiPolygon":
            parts = [("poly", [to_m(r) for r in p]) for p in g["coordinates"]]
        else:
            continue
        for kind, rings in parts:
            out.append((kind, rings, f["properties"]))
    return out
