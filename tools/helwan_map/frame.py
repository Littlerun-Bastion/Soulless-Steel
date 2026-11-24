"""Map frame: the map square, centred on the origin, and how real-world metres
map into it.

Settings come from inputs/map.json:
  map_m           width of the map square in metres (the map is map_m * 20 px)
  grid_n          pixels across the image grid the generator reads the
                  reference image into (about 2 m per pixel)
  geo_centre      [lat, lon] that geo.py measures real-world metres from
  image           the reference image (satellite or mockup), north up
  image_span_m    metres the image spans across
  image_centre_m  [x, y] real-world metres (east, south of geo_centre) of the
                  image's centre, found by fitting the image to the OSM streets
  image_rot_deg   the image's rotation against north, from the same fit
  grey_map, texture_map
                  optional quantile maps ([[from, to], ...]) that bring the
                  image's brightness and texture to the values the zone rules
                  were tuned on (see calibrate_image.py)
  border_m        width of the border band round the map's edge, in metres
                  (default 200). Mechs can't enter it; the generator fills it
                  like the rest of the map but puts no salvage sources, spawns
                  or exits in it. The play area is the map square shrunk by
                  border_m on every side.

Real-world metres go into the frame with the fit's offset and rotation, then
are scaled so the image's span fills the map.
"""
import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = json.load(open(os.path.join(HERE, "inputs", "map.json"), encoding="utf-8"))

PX_PER_M = 20.0
MAP_M = float(CONFIG["map_m"])
MAP_PX = MAP_M * PX_PER_M
MOCK_N = int(CONFIG["grid_n"])
FIT_SPAN_M = float(CONFIG["image_span_m"])
FIT_CX, FIT_CY = (float(v) for v in CONFIG["image_centre_m"])
FIT_ROT_DEG = float(CONFIG["image_rot_deg"])
SCALE = MAP_M / FIT_SPAN_M
BORDER_M = float(CONFIG.get("border_m", 200.0))
# Half the width of the play area, in map-frame metres.
PLAY_HALF_M = MAP_M / 2 - BORDER_M

_c, _s = np.cos(np.radians(FIT_ROT_DEG)), np.sin(np.radians(FIT_ROT_DEG))


def m_to_world(pts):
    """Real-world metres around geo_centre -> world px centred on the origin."""
    p = np.asarray(pts, float)
    x, y = p[:, 0] - FIT_CX, p[:, 1] - FIT_CY
    u, v = _c * x + _s * y, -_s * x + _c * y
    return np.stack([u, v], 1) * SCALE * PX_PER_M


def world_to_mock(pts):
    p = np.asarray(pts, float)
    return p / MAP_PX * MOCK_N + MOCK_N / 2


def in_play_area(x, y, margin=0.0):
    """True where a point (map-frame metres) is at least margin metres inside
    the play area."""
    lim = PLAY_HALF_M - margin
    return (np.abs(np.asarray(x)) <= lim) & (np.abs(np.asarray(y)) <= lim)


def image_path():
    return os.path.join(HERE, "inputs", CONFIG["image"])
