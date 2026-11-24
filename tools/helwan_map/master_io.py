"""Reads hand-made areas from helwan_master.tscn.

KeepOut       Polygon2D children of the master's KeepOut node: areas the
              generator keeps empty.
Markers       the exits, start positions, spawn zones and cyst sites (their
              positions): the generator keeps obstacles off them.
DistrictZones Polygon2D children of the master's DistrictZones node, each
              with a "district" metadata (metadata/district = "industrial" in
              the scene text) or a district property: areas whose district is
              painted by hand. A painted polygon wins over the generator.

Both parent nodes stay at the origin. Each polygon node's position, rotation,
scale and polygon are read from the scene text. Polygons come back as shapely
polygons in map-frame metres.
"""
import math
import os
import re

from shapely.geometry import Polygon
from shapely.ops import unary_union

PX_PER_M = 20.0
_NODE = re.compile(r'^\[node name="([^"]+)" type="Polygon2D" parent="([^"]+)"\]\s*$')
_NUMS = re.compile(r"-?\d+(?:\.\d+)?(?:e-?\d+)?")
_TEXT = re.compile(r'^"(.*)"$')


def _vec(text):
    """Numbers inside a Godot value such as Vector2(1, 2), skipping the type
    name (which has digits of its own)."""
    if "(" in text:
        text = text[text.index("(") + 1:]
    return [float(v) for v in _NUMS.findall(text)]


def read_polygons(master_path, parent):
    """(polygon, values) for every Polygon2D child of `parent`. values holds
    the node's other text properties (for example "district")."""
    if not os.path.exists(master_path):
        return []
    out = []
    cur = None
    with open(master_path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    for line in lines + ["["]:
        if line.startswith("["):
            if cur and len(cur["poly"]) >= 3:
                p = _to_polygon(cur)
                if not p.is_empty:
                    out.append((p, cur["values"]))
            m = _NODE.match(line)
            cur = None
            if m and m.group(2) == parent:
                cur = {"pos": (0.0, 0.0), "rot": 0.0, "scale": (1.0, 1.0), "poly": [], "values": {}}
            continue
        if cur is None or "=" not in line:
            continue
        key, val = (s.strip() for s in line.split("=", 1))
        if key == "position":
            cur["pos"] = tuple(_vec(val)[:2])
        elif key == "rotation":
            cur["rot"] = float(val)
        elif key == "scale":
            cur["scale"] = tuple(_vec(val)[:2])
        elif key == "polygon":
            v = _vec(val)
            cur["poly"] = list(zip(v[::2], v[1::2]))
        else:
            t = _TEXT.match(val)
            if t:
                cur["values"][key.removeprefix("metadata/")] = t.group(1)
    return out


def read_keep_outs(master_path):
    return [p for p, _ in read_polygons(master_path, "KeepOut")]


def read_district_zones(master_path):
    """(polygon, district name) for every painted district polygon, in scene
    order (a later polygon wins where two overlap)."""
    return [(p, v["district"]) for p, v in read_polygons(master_path, "DistrictZones") if "district" in v]


_MARKER = re.compile(r'^\[node name="([^"]+)" [^\]]*parent="(Exits|StartPositions|SpawnZones|CystSites)"')


def read_markers(master_path):
    """(name, x, y) in map-frame metres of every exit, start position, spawn
    zone and cyst site of the master scene."""
    if not os.path.exists(master_path):
        return []
    out, name = [], None
    with open(master_path, encoding="utf-8") as fh:
        for line in fh.read().splitlines():
            if line.startswith("["):
                m = _MARKER.match(line)
                name = m.group(1) if m else None
            elif name and line.startswith("position"):
                x, y = _vec(line.split("=", 1)[1])[:2]
                out.append((name, x / PX_PER_M, y / PX_PER_M))
                name = None
    return out


def _to_polygon(node):
    c, s = math.cos(node["rot"]), math.sin(node["rot"])
    sx, sy = node["scale"]
    px, py = node["pos"]
    pts = []
    for x, y in node["poly"]:
        x, y = x * sx, y * sy
        pts.append(((c * x - s * y + px) / PX_PER_M, (s * x + c * y + py) / PX_PER_M))
    return Polygon(pts).buffer(0)


def keep_out_union(master_path, margin_m=2.0):
    polys = read_keep_outs(master_path)
    if not polys:
        return Polygon()
    return unary_union(polys).buffer(margin_m)
