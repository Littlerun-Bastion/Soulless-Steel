"""Draws two review boards with the generator's own drawing code, on made-up
footprints, and renders them with render_preview.py:

  ruin_states.png    the same footprints (a house, an L house, a large roof)
                     intact, damaged, gutted and collapsed
  solar_variants.png the six solar panel installations: tilted rack rows,
                     raised canopy, low ballasted rows, a small house set,
                     flush on a tile roof, a ground array

Usage: python review_boards.py <project> <out dir>
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np
from shapely import affinity
from shapely.geometry import Polygon, box

import buildings as bl
import render_preview
import salvage
import solar
import style

GROUND_V = 0.16


def board_work(out_dir, name):
    d = os.path.join(out_dir, "board_" + name)
    os.makedirs(d, exist_ok=True)
    return d


def finish(L, S, work, project, png, window, scale):
    manifest, _ = L.write(work)
    with open(os.path.join(work, "props.json"), "w", encoding="utf-8") as fh:
        json.dump({"kinds": [], "items": []}, fh)
    S.write(os.path.join(work, "salvage.json"))
    render_preview.render(work, project, png, window, scale, show_props=False, notes=True)


def ruin_board(project, out_dir):
    shapes = [
        box(0, 0, 12, 9),
        Polygon([(0, 0), (14, 0), (14, 6), (7, 6), (7, 13), (0, 13)]),
        box(0, 0, 40, 24),
    ]
    buildings = []
    for col, state in enumerate((bl.INTACT, bl.DAMAGED, bl.GUTTED, bl.COLLAPSED)):
        y = 0.0
        for k, g in enumerate(shapes):
            p = affinity.translate(g, col * 52.0, y)
            buildings.append(bl.Building(p, 0.12, "big" if k == 2 else "house", state=state))
            y += g.bounds[3] - g.bounds[1] + 10.0
    S = salvage.Salvage()
    L = bl.build_layers(Polygon(), [], buildings, (), S)
    finish(L, S, board_work(out_dir, "ruins"), project, os.path.join(out_dir, "ruin_states.png"),
           (-6, -6, 206, 72), 8)


def solar_board(project, out_dir):
    rng = np.random.default_rng(5)
    L = style.Layers()
    S = salvage.Salvage()
    big = box(0, 0, 44, 26)
    specs = [("tilted rack rows", solar.tilted_rows, big, False),
             ("raised canopy", solar.canopy, box(52, 0, 96, 26), True),
             ("low ballasted rows", solar.low_rows, box(104, 0, 168, 18), False)]
    for _, fn, g, post in specs:
        L.add_building(g)
        got = []
        hook = (lambda R, fn=fn: got.append(fn(R, rng)))
        style.draw_big(L, g, 0.12, rng, pre=None if post else hook, post=hook if post else None)
        if got and got[0] is not None:
            bl.add_poly_source(S, "solar_panels", got[0][0], L.bid, got[0][1])
    house = box(0, 34, 11, 43)
    L.add_building(house)
    hits = []
    style.draw_house(L, house, 0.12, rng, pre=lambda R: hits.append(solar.house_set(R, rng)))
    if hits and hits[0] is not None:
        bl.add_poly_source(S, "solar_panels", hits[0][0], L.bid, hits[0][1])
    tile = box(20, 34, 34, 44)
    L.add_building(tile)
    shape, rects, ang, c = style.roof_shape(tile)
    style.draw_tiled_house(L, tile, 0.12, rng, rects, ang, c)
    got = solar.flush_on_tiles(L, rects, ang, c, rng, style.chunk_key(tile))
    if got is not None:
        bl.add_poly_source(S, "solar_panels", got[0], L.bid, got[1])
    L.bid = -1
    ground = box(44, 30, 110, 64)
    got = solar.ground_array(L, ground, 0.0, rng, None)
    if got is not None:
        bl.add_poly_source(S, "solar_panels", got[0], -1, got[1])
    finish(L, S, board_work(out_dir, "solar"), project, os.path.join(out_dir, "solar_variants.png"),
           (-4, -4, 172, 68), 8)


if __name__ == "__main__":
    project, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    ruin_board(project, out)
    solar_board(project, out)
    print("wrote", os.path.join(out, "ruin_states.png"), os.path.join(out, "solar_variants.png"))
