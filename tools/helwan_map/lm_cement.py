"""The cement works in the south-west (industrial.py builds them inside
density.CEMENT_BOX_M; OSM names the plant "Helwan Cement Plant"): this
module names the place and stands its tall parts up in the talls, so the
works can be seen and steered by from far off. It takes no land and builds
nothing on the ground. The name covers the works' fenced compounds and the
OSM plant, not the housing round them (works_outline).

  preheater towers  the "tower" buildings of the kiln lines rise to about
                    50 m: a shaft with a riser duct and platform rings
  silos             the "silo" buildings rise as cylinders of about 28 m
                    with lit lids
  chimneys          the "chimney" buildings rise as stacks of about 65 m

What a building's ruin state leaves standing is decided when it is drawn
(the states are assigned after the site modules run): a gutted tower or
silo stands at about half height with a broken top, a collapsed one has no
tall part at all, and one the overlap check dropped has none either.
"""
import numpy as np
from shapely.geometry import LinearRing, LineString, Point, box
from shapely.ops import nearest_points, unary_union

import density
import industrial
import kit
import lmkit as K
import ruins
import style
from frame import PLAY_HALF_M
from gen_city import block_rng

NAME = "Helwan Cement Works"
TOWER_H = 50.0
SILO_H = 28.0
CHIMNEY_H = 65.0
# How far from the works' box the OSM plant outline may lie and still be
# part of the named place.
PLANT_NEAR_M = 300.0
KINDS = ("tower", "silo", "chimney")
# Drawn top heights of a standing and of a gutted tall part, by kind; the
# lower ones are drawn first (see build's draw).
TOPS = {"tower": (TOWER_H + 4.0, TOWER_H * 0.55), "silo": (SILO_H, SILO_H * 0.5),
        "chimney": (CHIMNEY_H, CHIMNEY_H * 0.5)}
# The seed industrial.build gives block_rng when it tiles a block into
# compound plots.
PLOT_SEED = 41
# The named place reaches this far out from the works' fences, and bays
# narrower than twice CLOSE_M between them are filled.
GROW_M = 12.0
CLOSE_M = 30.0


def works_outline(site):
    """The ground the name covers, from the whole map's layout (so a window
    run gives the outline of a full run): the compound plots that
    industrial.build lays out in the cement works' box, and the OSM plant
    outline next to them, grown by GROW_M and closed, inside the play area.
    A part still apart from the largest (a compound across a street) joins
    it by a strip 2 * GROW_M wide, so the outline is one polygon. None when
    the works are not on the map."""
    x0, y0, x1, y1 = density.CEMENT_BOX_M
    play = box(-PLAY_HALF_M, -PLAY_HALF_M, PLAY_HALF_M, PLAY_HALF_M)
    works = box(x0, y0, x1, y1)
    if not works.intersects(play):
        return None
    plots = []
    for blk in site.full_layout["blocks"]:
        if blk.area < industrial.MIN_BLOCK_M2 or not blk.intersects(works) or \
                site.districts.share(blk, industrial.INDUSTRIAL) < industrial.MIN_SHARE:
            continue
        for plot, _ in industrial.plots(blk, block_rng(PLOT_SEED, blk))[0]:
            area = kit.largest(plot.buffer(-industrial.FENCE_INSET_M, join_style="mitre"))
            if area is not None and area.area >= industrial.MIN_BLOCK_M2 * 0.7 and industrial.in_cement_works(area):
                plots.append(area)
    if not plots:
        return None
    plant = [g for g, p in K.osm_polys(site, lambda p: p.get("landuse") == "industrial" and
                                       "Cement Plant" in str(p.get("name", "")), works.buffer(PLANT_NEAR_M))]
    ground = unary_union(plots + plant).buffer(GROW_M, join_style="mitre")
    parts = sorted(style.polys(ground.buffer(CLOSE_M).buffer(-CLOSE_M).intersection(play)), key=lambda g: -g.area)
    if not parts:
        return None
    out = parts[0]
    for g in parts[1:]:
        a, b = nearest_points(g, out)
        out = unary_union([out, g, LineString([a, b]).buffer(GROW_M, cap_style="flat").buffer(0.5)])
    return kit.largest(out.intersection(play))


def build(site, masks):
    x0, y0, x1, y1 = density.CEMENT_BOX_M
    outline = works_outline(site)
    if outline is None:
        return {"built": False, "why": "the works are outside the play area"}
    site.add_landmark(NAME, "works", outline)
    tall = []
    for b in site.buildings:
        if b.kind not in KINDS or b.opts.get("stage") != "industrial":
            continue
        c = b.poly.centroid
        if x0 <= c.x <= x1 and y0 <= c.y <= y1:
            tall.append(b)
    stats = {"built": bool(tall), "outline_ha": round(outline.area / 1e4, 1),
             "towers": sum(b.kind == "tower" for b in tall), "silos": sum(b.kind == "silo" for b in tall),
             "chimneys": sum(b.kind == "chimney" for b in tall)}
    if not tall:
        return stats

    def draw(L):
        # The drawers run after the overlap check, which can drop a building:
        # only the ones still on the map stand up. The talls have no depth
        # test (a triangle drawn later covers an earlier one), so the lower
        # parts are drawn first and a tower leaning over a silo covers it.
        on_map = {id(b) for b in site.buildings}
        stand = [b for b in tall if id(b) in on_map and b.state != ruins.COLLAPSED]
        stand.sort(key=lambda b: TOPS[b.kind][b.state == ruins.GUTTED])
        for b in stand:
            broken = b.state == ruins.GUTTED
            if b.kind == "tower":
                _tower(L, b, broken)
            elif b.kind == "silo":
                _silo(L, b, broken)
            else:
                _chimney(L, b, broken)
    site.drawers.append(draw)
    return stats


def _tower(L, b, broken):
    h = TOWER_H * (0.55 if broken else 1.0)
    g = b.poly
    L.tall_prism(g, 0.0, h, 0.2, 0.3)
    c = g.centroid
    F = g.minimum_rotated_rectangle
    ring = np.asarray(F.exterior.coords)[:4]
    e = ring[1] - ring[0]
    ang = float(np.arctan2(e[1], e[0]))
    side = float(np.hypot(*e))
    P = K.local(c.x, c.y, ang)
    for hp in np.arange(12.0, h - 2.0, 12.0):
        L.tall_prism(K.rect_at(c.x, c.y, ang, side + 2.2, side + 2.2), hp, hp + 0.5, 0.26, 0.38)
        L.tall_prism(g, hp + 0.5, min(hp + 12.0, h), 0.2, 0.3)
    dx, dy = P(side / 2 + 1.2, 0.0)
    L.tall_post(dx, dy, 1.8, 0.0, h * 0.95, 0.24, 0.34, ang=np.degrees(ang))
    if not broken:
        L.tall_prism(K.rect_at(c.x, c.y, ang, side * 0.5, side * 0.5), h, h + 4.0, 0.22, 0.4)
    else:
        L.fill("talls", K.ngon(c.x, c.y, side * 0.3, 5, 0.4), 0.05, h=h)


def _silo(L, b, broken):
    h = SILO_H * (0.5 if broken else 1.0)
    g = b.poly.simplify(0.15)
    L.tall_prism(g, 0.0, h, 0.22, 0.32)
    c = g.centroid
    r = float(np.sqrt(g.area / np.pi))
    if broken:
        L.fill("talls", Point(c.x, c.y).buffer(r * 0.7, quad_segs=4), 0.04, h=h)
        return
    L.fill("talls", Point(c.x, c.y).buffer(r * 0.82, quad_segs=6), 0.36, h=h)
    L.fill("talls", LinearRing(Point(c.x, c.y).buffer(r * 0.82, quad_segs=6).exterior.coords).buffer(0.1), 0.44,
           h=h)
    L.fill("talls", Point(c.x + r * 0.3, c.y).buffer(0.5, quad_segs=2), 0.2, h=h + 0.2)


def _chimney(L, b, broken):
    h = CHIMNEY_H * (0.5 if broken else 1.0)
    c = b.poly.centroid
    r = max(1.6, min(3.2, float(np.sqrt(b.poly.area / np.pi)) * 0.6))
    L.tall_prism(K.ngon(c.x, c.y, r, 12), 0.0, h, 0.24, 0.3)
    L.tall_prism(K.ngon(c.x, c.y, r * 1.12, 12), h - 3.0, h - 2.2, 0.3, 0.4)
    L.fill("talls", K.ngon(c.x, c.y, r * 0.7, 12), 0.02, h=h)
