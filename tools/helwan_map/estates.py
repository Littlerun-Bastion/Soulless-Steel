"""Public housing estates ("masaken" in Helwan): rows of identical four- to
six-storey slab blocks with open ground between the rows.

Where: the PLACES where the satellite image shows such rows, then, while
there are fewer than MIN_ESTATES, other large residential street blocks
made mostly of generated lots (find_more). An estate lays its rows out over
the street blocks inside its box, SETBACK_M in from the roads, less the land
other site modules claimed and the large roofs (real buildings) in it. Its
land (estate_land) is the ground its rows and lanes use: within half a row
gap of the blocks, the lanes out to the street, and every generated lot that
reaches into these, which is removed. Lots beyond it stay.

One design per estate (design()): every block of an estate has the same
depth, length, plan (a plain slab, an L or a U with its wings towards the
back), stair cores and roof (a stair head over each core and the same water
tanks beside it); designs differ between estates. A block is a building of
kind "estate", drawn by draw_block: halo, an interior of flats with the
stairwells at the front, and the roof; ruins follow the usual rules
(ruins.py). Dish rows, shacks and pigeon towers vary from block to block.

The rows run along the street block's long axis, or along the place's own
row angle. In the middle of the open ground between two rows (past the wing
tips) there is an access lane (LANE_W_M, every other gap, with cars parked
along it) or a footpath; both run on to the street when it is near. Every
block's stair cores have an entrance path to the front, the open ground is
worn (darker ground fills), with a few bare trees, washing lines and
rubbish, and KIOSKS kiosks (hut props) at the lane mouths by the street.
Lanes and paths are kept clear of the generic props (Site.solid_extra).
"""
import numpy as np
import shapely
from shapely import STRtree, prepare
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

import buildings as bl
import construction
import district_life
import kit
import props
import ruins
import style
from frame import PLAY_HALF_M
from gen_city import block_rng, min_width, rect_fill

## Estates where the satellite image shows rows of slab blocks: name, the
## box they fill (x0, y0, x1, y1, map metres) and the direction of the rows
## in degrees (None: each street block's long axis).
PLACES = [
    ("north_diagonal", (500.0, -2030.0, 800.0, -1690.0), None),
    ("north_open", (205.0, -1990.0, 380.0, -1520.0), 3.0),
    ("west_rows", (-1880.0, -1865.0, -1710.0, -1630.0), -6.0),
    ("west_loop", (-2370.0, -1370.0, -2225.0, -1155.0), None),
]
## The fewest and most estates on the map; find_more adds street blocks
## while fewer than MIN_ESTATES of the PLACES were built.
MIN_ESTATES = 6
MAX_ESTATES = 8
## find_more: street block area (m2), least rectangle fill and width (m),
## least residential share, least share of it covered by generated lots,
## and the least distance (m) between two estates.
MORE_AREA_M2 = (9000.0, 45000.0)
MORE_FILL = 0.72
MORE_MIN_WIDTH_M = 70.0
MORE_RESIDENTIAL = 0.85
MORE_LOTS_SHARE = 0.25
MORE_SPACING_M = 650.0
MARGIN_M = 250.0
## Street blocks with this share of the industrial, market or farmland
## district are rebuilt by those modules; estates keep out of them.
REBUILT_SHARE = 0.45
## How far the blocks stay from the roads (m), and from large roofs left
## in an estate.
SETBACK_M = 4.0
BIG_ROOF_CLEAR_M = 8.0
## A street block piece with fewer blocks than this keeps its lots.
MIN_PIECE_BLOCKS = 2
LANE_W_M = 6.0
## Designs tried per estate; the one that fills the most ground is built
## (a later one only when it fills DESIGN_GAIN times more than the best so
## far, so narrow street blocks get a design that fits them).
DESIGN_TRIES = 6
DESIGN_GAIN = 1.15
PATH_W_M = 2.4
## A lane or path runs on to the street block's edge when that is at most
## LANE_REACH_M beyond the end it would have past its blocks.
LANE_REACH_M = 36.0
## An estate's land reaches half a row gap plus USE_PAD_M from its blocks.
USE_PAD_M = 1.0
## A lot is removed when it reaches into the estate's land by more than
## LOT_TOUCH_M2, or comes within LOT_CLEAR_M of a block or onto a lane.
LOT_TOUCH_M2 = 2.0
LOT_CLEAR_M = 3.0
## Cars parked along an access lane: one per CAR_STEP_M at the design's
## chance (lane_cars), at most MAX_CARS per estate.
CAR_STEP_M = 5.6
MAX_CARS = 28
TREE_CHANCE = 0.35
## Kiosks per estate (fewest, most): at lane and path mouths within
## KIOSK_ROAD_M of a street, else along the estate's edge by a street;
## at least KIOSK_SPACING_M apart.
KIOSKS = (1, 3)
KIOSK_ROAD_M = 12.0
KIOSK_SPACING_M = 30.0

PAVE_V = 0.22
LANE_V = 0.245
WORN_V = 0.1
## The smallest worn patch (radius, m): a patch shrinks to fit the open
## ground round its centre, and is left out below this.
PATCH_MIN_M = 2.0


def design(rng):
    """One estate's block design (all its blocks are identical)."""
    cores = int(rng.choice([2, 3, 4], p=[0.15, 0.5, 0.35]))
    core_step = float(rng.uniform(13.0, 16.0))
    shape = str(rng.choice(["slab", "L", "U"], p=[0.5, 0.28, 0.22]))
    gap = float(rng.uniform(20.0, 28.0))
    if shape != "slab":
        gap = max(gap, 24.0)
    depth = float(rng.uniform(10.0, 13.0))
    wing = float(min(rng.uniform(8.0, 12.0), gap - 14.0))
    if wing < 7.0:
        shape = "slab"
    floors = int(rng.integers(4, 7))
    return {
        "cores": cores, "core_step": core_step, "length": cores * core_step + 2.0, "depth": depth,
        "shape": shape, "wing": wing if shape != "slab" else 0.0, "wing_w": depth * 0.9, "gap": gap,
        "end_gap": float(rng.uniform(14.0, 20.0)), "floors": floors, "mv": float(rng.uniform(0.16, 0.3)),
        "tanks": str(rng.choice(["stand", "cluster"])), "lane_cars": float(rng.uniform(0.24, 0.38)),
        "shack": float(rng.uniform(0.15, 0.45)), "pigeons": float(rng.uniform(0.0, 0.15)),
    }


def outline(d):
    """The block's outline in its own frame: x along the block, y across, the
    front (stair cores) towards -y, wings towards +y."""
    hl, hd, w, ww = d["length"] / 2, d["depth"] / 2, d["wing"], d["wing_w"]
    if d["shape"] == "L":
        return [(-hl, -hd), (hl, -hd), (hl, hd + w), (hl - ww, hd + w), (hl - ww, hd), (-hl, hd)]
    if d["shape"] == "U":
        return [(-hl, -hd), (hl, -hd), (hl, hd + w), (hl - ww, hd + w), (hl - ww, hd), (-hl + ww, hd),
                (-hl + ww, hd + w), (-hl, hd + w)]
    return [(-hl, -hd), (hl, -hd), (hl, hd), (-hl, hd)]


def core_xs(d):
    return [-d["length"] / 2 + 1.0 + d["core_step"] * (k + 0.5) for k in range(d["cores"])]


def intervals(area_local, y0, y1, steps=5):
    """The x intervals where the strip from y0 to y1 lies inside a polygon
    (local frame)."""
    x0, _, x1, _ = area_local.bounds
    out = None
    for y in np.linspace(y0, y1, steps):
        cut = LineString([(x0 - 1, y), (x1 + 1, y)]).intersection(area_local)
        segs = []
        for g in getattr(cut, "geoms", [cut]):
            if g.geom_type == "LineString" and not g.is_empty:
                xs = [c[0] for c in g.coords]
                segs.append((min(xs), max(xs)))
        if out is None:
            out = segs
        else:
            out = [(max(a, c), min(b, e)) for a, b in out for c, e in segs if min(b, e) > max(a, c)]
        if not out:
            return []
    return out


def layout(area, ang, d):
    """Rows of identical blocks in an area. Returns the frame and the rows:
    lists of (local centre x, y) per row, plus the rows' y."""
    F = kit.Frame(area, ang)
    loc = F.local(area)
    ext = d["depth"] + d["wing"]
    span = F.y1 - F.y0
    pitch = d["depth"] + d["gap"]
    if span < ext:
        return F, []
    n = int((span - ext) // pitch) + 1
    y_first = F.y0 + (span - (ext + (n - 1) * pitch)) / 2
    rows = []
    for i in range(n):
        y = y_first + i * pitch
        centres = []
        for a, b in intervals(loc, y, y + ext):
            k = int((b - a + d["end_gap"]) // (d["length"] + d["end_gap"]))
            if k <= 0:
                continue
            x = a + (b - a - (k * d["length"] + (k - 1) * d["end_gap"])) / 2
            for j in range(k):
                centres.append((x + j * (d["length"] + d["end_gap"]) + d["length"] / 2, y + d["depth"] / 2))
        rows.append((y, centres))
    return F, rows


def block_poly(F, d, cx, cy):
    return Polygon([F.pt(cx + px, cy + py) for px, py in outline(d)])


def usable_pieces(site, region, big_tree, big_polys, claimed):
    """The street blocks inside a region, SETBACK_M in from their edges,
    less the claimed land and the large roofs; with the street block piece
    each one came from."""
    out = []
    for blk in site.full_layout["blocks"]:
        if not blk.intersects(region):
            continue
        piece = blk.intersection(region)
        if piece.area < 1500 or site.districts.share(piece, 0) < 0.5:
            continue
        if any(site.districts.share(blk, code) >= REBUILT_SHARE for code in (1, 2, 3)):
            continue
        inner = piece.buffer(-SETBACK_M, join_style="mitre")
        near = [big_polys[i] for i in big_tree.query(piece)]
        if near:
            inner = inner.difference(unary_union(near).buffer(BIG_ROOF_CLEAR_M))
        if claimed is not None:
            inner = inner.difference(claimed.buffer(4.0))
        for g in style.polys(inner):
            if g.area >= 1200:
                out.append((g, piece))
    return out


def find_more(site, n, chosen, big_tree, big_polys, lot_tree, lot_polys, claimed):
    """Up to n more estates in large, regular residential street blocks
    made mostly of generated lots, spread out from the chosen ones."""
    cands = []
    lim = PLAY_HALF_M - MARGIN_M
    for blk in site.full_layout["blocks"]:
        a = blk.area
        if not MORE_AREA_M2[0] <= a <= MORE_AREA_M2[1]:
            continue
        x0, y0, x1, y1 = blk.bounds
        if min(x0, y0) < -lim or max(x1, y1) > lim:
            continue
        if rect_fill(blk) < MORE_FILL or min_width(blk) < MORE_MIN_WIDTH_M:
            continue
        if site.districts.share(blk, 0) < MORE_RESIDENTIAL:
            continue
        if claimed is not None and claimed.intersects(blk):
            continue
        big = sum(big_polys[i].intersection(blk).area for i in big_tree.query(blk))
        if big > 0.03 * a:
            continue
        lots = sum(lot_polys[i].area for i in lot_tree.query(blk) if blk.contains(lot_polys[i].centroid))
        if lots < MORE_LOTS_SHARE * a:
            continue
        c = blk.centroid
        cands.append((-(rect_fill(blk) * min(lots / a, 0.6)), round(c.x, 1), round(c.y, 1), blk))
    cands.sort(key=lambda t: t[:3])
    out = []
    for _, x, y, blk in cands:
        if len(out) >= n:
            break
        if any(np.hypot(x - px, y - py) < MORE_SPACING_M for px, py in chosen):
            continue
        chosen.append((x, y))
        out.append(blk)
    return out


def choose(site):
    """The estates over the whole map: [(name, region, row angle)]."""
    claimed = site.claimed()
    reserved = construction.reserved_area(site)
    if reserved is not None:
        claimed = reserved if claimed is None else unary_union([claimed, reserved])
    big_polys = site.full_layout["big"]
    big_tree = STRtree(big_polys)
    out, chosen = [], []
    for name, (x0, y0, x1, y1), ang in PLACES:
        region = box(x0, y0, x1, y1)
        pieces = usable_pieces(site, region, big_tree, big_polys, claimed)
        if sum(g.area for g, _ in pieces) < 4000:
            continue
        out.append((name, region, ang, pieces))
        chosen.append(((x0 + x1) / 2, (y0 + y1) / 2))
    if len(out) < MIN_ESTATES:
        lot_polys = site.full_layout["lots"]
        lot_tree = STRtree(lot_polys)
        for k, blk in enumerate(find_more(site, MAX_ESTATES - len(out), chosen, big_tree, big_polys, lot_tree,
                                          lot_polys, claimed)):
            if len(out) >= MIN_ESTATES:
                break
            pieces = usable_pieces(site, blk.buffer(1.0), big_tree, big_polys, claimed)
            if sum(g.area for g, _ in pieces) >= 4000:
                c = blk.centroid
                out.append((f"block_{int(c.x)}_{int(c.y)}", blk.buffer(1.0), None, pieces))
    return out


def pick_design(pieces, ang, rng):
    best, best_area = None, -1.0
    for _ in range(DESIGN_TRIES):
        d = design(rng)
        foot = Polygon(outline(d)).area
        filled = sum(len(c) for area, _ in pieces for _, c in layout(area, ang, d)[1]) * foot
        if best is None or filled > best_area * DESIGN_GAIN:
            best, best_area = d, filled
    return best


def build(site, made):
    """Lays out every estate of the map, claims the land of each one that
    has room, and builds the ones that touch the window. The claims are
    made in every run (outside the window with the whole map's lots and
    large roofs standing in for the buildings, see estate_land), so a window
    run leaves about the same land to the building sites and the modules
    after them as the full run. made: the module's stats dict ("names":
    every estate claimed; the counts: the estates built)."""
    est = made.setdefault("estates", {"built": 0, "blocks": 0, "lots_removed": 0, "cars": 0, "kiosks": 0,
                                      "names": []})
    bl.KINDS["estate"] = (block_roof, False, style.HALO_HOUSE_M, style.counted("estates_all", draw_block))
    stand_in = None
    for name, region, ang, pieces in choose(site):
        d = pick_design(pieces, ang, block_rng(401, region))
        blocks, grounds = [], []
        for area, piece in pieces:
            F, rows = layout(area, ang, d)
            polys_rows = []
            for y, centres in rows:
                row = []
                for cx, cy in centres:
                    poly = block_poly(F, d, cx, cy)
                    if area.contains(poly) and site.is_free(poly, 2.0):
                        row.append((cx, cy, poly))
                polys_rows.append((y, row))
            if sum(len(r) for _, r in polys_rows) < MIN_PIECE_BLOCKS:
                continue
            grounds.append((area, piece, F, polys_rows))
            blocks += [p for _, r in polys_rows for *_, p in r]
        if len(blocks) < 3:
            continue
        est["names"].append(name)
        if not site.in_window(region):
            if stand_in is None:
                lay = site.full_layout
                stand_in = [(STRtree(lay["lots"]), lay["lots"], True), (STRtree(lay["big"]), lay["big"], False)]
            for area, piece, F, rows in grounds:
                land, _ = estate_land(site, area, piece, rows, lane_parts(F, area, piece, rows, d), d, stand_in)
                site.claim(land, f"fabric:estate:{name}")
            continue
        est["built"] += 1
        rng = block_rng(409, region)
        cars = [MAX_CARS]
        mouths, lands, lane_polys = [], [], []
        for area, piece, F, rows in grounds:
            lanes = lane_parts(F, area, piece, rows, d)
            land, gone = estate_land(site, area, piece, rows, lanes, d)
            est["lots_removed"] += gone
            site.clear_area(land)
            site.claim(land, f"fabric:estate:{name}")
            for y, row in rows:
                for cx, cy, poly in row:
                    c = Point(F.pt(cx, cy))
                    b = bl.Building(poly, d["mv"], "estate", design=d, frame=(c.x, c.y, F.ang), stage="fabric")
                    site.buildings.append(b)
                    est["blocks"] += 1
            est["cars"] += grounds_props(site, land, F, rows, lanes, d, rng, cars)
            site.drawers.append(style.counted("estates_all", grounds_drawer(
                land, blocks, F, rows, lanes, d, int(block_rng(419, area).integers(1 << 30)))))
            mouths += lane_mouths(site, F, lanes)
            lands.append(land)
            lane_polys += [g for *_, g in lanes]
        est["kiosks"] += kiosks(site, mouths, unary_union(lands), unary_union(blocks), unary_union(lane_polys)
                                if lane_polys else None, rng)


def lane_rects(F, loc, rows, d):
    """The paths and lanes of an estate piece, in its frame: (kind, x0, y0,
    x1, y1) with kind "lane" or "path", one in the middle of the open ground
    in front of each row after the first (between the wing tips of the row
    behind and the row's front), lanes in every other gap. One runs on past
    its blocks to the area's edge and SETBACK_M beyond (the street) when
    that is at most LANE_REACH_M further. loc: the area in the frame."""
    out = []
    for i in range(1, len(rows)):
        (ya, ra), (yb, rb) = rows[i - 1], rows[i]
        if not ra and not rb:
            continue
        xs = [cx for cx, _, _ in ra + rb]
        x0, x1 = min(xs) - d["length"] / 2 - 8.0, max(xs) + d["length"] / 2 + 8.0
        yc = yb - (d["gap"] - d["wing"]) / 2
        lane = i % 2 == 1
        w = LANE_W_M if lane else PATH_W_M
        e0, e1 = x0, x1
        for a, b in intervals(loc, yc - w / 2, yc + w / 2, 3):
            if b < x0 or a > x1:
                continue
            if x0 - a <= LANE_REACH_M:
                e0 = min(e0, a - SETBACK_M - 1.0)
            if b - x1 <= LANE_REACH_M:
                e1 = max(e1, b + SETBACK_M + 1.0)
        out.append(("lane" if lane else "path", e0, yc - w / 2, e1, yc + w / 2))
    return out


def lane_parts(F, area, piece, rows, d):
    """The lanes and paths of an estate piece clipped to its street block
    piece: (kind, local x0, y0, x1, y1, polygon) per part."""
    reach = area.buffer(SETBACK_M, join_style="mitre").intersection(piece)
    out = []
    for kind, x0, y0, x1, y1 in lane_rects(F, F.local(area), rows, d):
        for part in style.polys(F.rect(x0, y0, x1, y1).intersection(reach)):
            if part.area < 4.0:
                continue
            lx = [F.to_local(px, py)[0] for px, py in part.exterior.coords]
            out.append((kind, min(lx), y0, max(lx), y1, part))
    return out


def estate_land(site, area, piece, rows, lanes, d, stand_in=None):
    """The land an estate piece uses: within half a row gap (plus USE_PAD_M)
    of its blocks and its lanes, inside the street block piece, off the
    whole map's road concrete (street blocks are cut before the junction
    patches are added to the roads); the generated lots that reach into it
    are removed and their land added. stand_in, for an estate that is only
    claimed: [(STRtree, polygons, are lots)] of the whole map's lots and
    large roofs, read in place of site.buildings, which is left as it is.
    Returns (land, lots removed)."""
    polys = [p for _, r in rows for *_, p in r]
    lane_g = [g for *_, g in lanes]
    u = d["gap"] / 2 + USE_PAD_M
    land = unary_union([p.buffer(u, join_style="mitre") for p in polys] + lane_g)
    land = land.intersection(area.buffer(SETBACK_M, join_style="mitre")).intersection(piece)
    hard = unary_union([p.buffer(LOT_CLEAR_M, join_style="mitre") for p in polys] + lane_g)
    prepare(land)
    prepare(hard)

    def goes(poly, lot):
        return lot and (hard.intersects(poly) or land.intersection(poly).area > LOT_TOUCH_M2)

    gone, kept = [], []
    if stand_in is not None:
        for tree, geoms, lots in stand_in:
            for i in tree.query(land, predicate="intersects"):
                (gone if goes(geoms[i], lots) else kept).append(geoms[i])
    else:
        lx0, ly0, lx1, ly1 = land.bounds
        keep = []
        for b in site.buildings:
            x0, y0, x1, y1 = b.poly.bounds
            if x1 > lx0 and x0 < lx1 and y1 > ly0 and y0 < ly1 and land.intersects(b.poly):
                if goes(b.poly, b.opts.get("stage") == "lots"):
                    gone.append(b.poly)
                    continue
                kept.append(b.poly)
            keep.append(b)
        site.buildings = keep
    if gone:
        land = unary_union([land] + gone).intersection(piece)
    others = site.claimed()
    if others is not None:
        land = land.difference(others)
    if kept:
        land = land.difference(unary_union(kept))
    roads = site.full_roads_near(land, 1.0)
    if roads is not None:
        land = land.difference(roads)
    land = unary_union([g for g in style.polys(land) if g.area >= 20.0])
    return land, len(gone)


def grounds_props(site, land, F, rows, lanes, d, rng, cars_left):
    """Cars along the lanes, trees along the paths, washing lines and
    rubbish by the blocks. cars_left: [cars the estate may still park].
    Returns the cars placed."""
    P = site.props
    blocks = unary_union([p for _, r in rows for *_, p in r])
    prepare(blocks)
    prepare(land)
    lim = PLAY_HALF_M - 2.0
    cars = 0
    for kind, x0, y0, x1, y1, _ in lanes:
        yc = (y0 + y1) / 2
        if kind == "lane":
            side = 1.0 if rng.random() < 0.5 else -1.0
            for x in np.arange(x0 + 4.0, x1 - 4.0, CAR_STEP_M):
                if cars_left[0] <= 0 or rng.random() > d["lane_cars"]:
                    continue
                variant, size = props.pick_vehicle("vehicle", rng)
                px, py = F.pt(x, yc + side * (LANE_W_M / 2 - 1.1))
                ang = F.rad + (np.pi if rng.random() < 0.5 else 0.0) + rng.normal(0, 0.04)
                rect = props.car_rect(px, py, ang, size)
                if abs(px) > lim or abs(py) > lim or not land.contains(rect) or rect.intersects(blocks):
                    continue
                if not P.clear_of(px, py, size[0] / 2):
                    continue
                k = "vehicle_wreck" if rng.random() < 0.1 else "vehicle"
                n = props.add_vehicle(P, site.salvage, k, px, py, ang, size, variant)
                cars += n
                cars_left[0] -= n
        else:
            for x in np.arange(x0 + 5.0, x1 - 5.0, rng.uniform(9.0, 13.0)):
                if rng.random() > TREE_CHANCE:
                    continue
                px, py = F.pt(x, yc + rng.choice([-1, 1]) * rng.uniform(2.8, 4.5))
                s = rng.uniform(7.0, 10.0)
                if land.contains(Point(px, py)) and not blocks.intersects(Point(px, py).buffer(2.5)) and \
                        P.clear_of(px, py, s * 0.3, ("tree",)) and abs(px) < lim and abs(py) < lim:
                    P.add("tree", px, py, rng.uniform(0, 2 * np.pi), (s, s))
    for y, row in rows:
        for cx, cy, poly in row:
            for _ in range(int(rng.integers(0, 3))):
                name = str(rng.choice(["washing", "washing", "rubbish", "tyres", "crates"]))
                v, size = district_life.variant_of("clutter", name)
                lx = cx + rng.uniform(-d["length"] / 2, d["length"] / 2)
                ly = cy + rng.choice([-1, 1]) * (d["depth"] / 2 + rng.uniform(1.6, 3.5))
                px, py = F.pt(lx, ly)
                if v >= 0 and land.contains(Point(px, py)) and not blocks.intersects(Point(px, py).buffer(1.2)) and \
                        P.clear_of(px, py, max(size) / 2 + 0.3) and abs(px) < lim and abs(py) < lim:
                    P.add("clutter", px, py, F.rad + rng.normal(0, 0.1), size, v)
    for *_, g in lanes:
        site.solid_extra.append(g)
    return cars


def lane_mouths(site, F, lanes):
    """Kiosk spots beside the ends of the lanes and paths that open onto a
    street: (x, y, angle) a few metres in from the street, either side."""
    out = []
    for kind, x0, y0, x1, y1, _ in lanes:
        yc = (y0 + y1) / 2
        off = (y1 - y0) / 2 + 2.2
        for xe, dx in ((x0, 1.0), (x1, -1.0)):
            ex, ey = F.pt(xe, yc)
            roads = site.road_union_near(Point(ex, ey), KIOSK_ROAD_M)
            if roads is None or roads.distance(Point(ex, ey)) > KIOSK_ROAD_M:
                continue
            for side in (-1.0, 1.0):
                px, py = F.pt(xe + dx * (SETBACK_M + 4.0), yc + side * off)
                out.append((px, py, F.rad))
    return out


def edge_spots(site, land, rng):
    """Kiosk spots along an estate's edge where a street passes, every 8 m
    and 3.5 m in, in a random order: (x, y, angle along the edge)."""
    out = []
    for g in style.polys(land.buffer(-3.5, join_style="mitre")):
        ring = g.exterior
        for t in np.arange(0.0, ring.length, 8.0):
            p = ring.interpolate(t)
            roads = site.road_union_near(p, SETBACK_M + 6.0)
            if roads is not None and roads.distance(p) <= SETBACK_M + 6.0:
                nxt = ring.interpolate(min(t + 1.0, ring.length))
                out.append((p.x, p.y, float(np.arctan2(nxt.y - p.y, nxt.x - p.x))))
    return [out[i] for i in rng.permutation(len(out))]


def kiosks(site, mouths, land, blocks, lanes, rng):
    """KIOSKS kiosks (hut props) for an estate: at the lane mouths, else
    along the estate's edge where a street passes. Returns how many."""
    want = int(rng.integers(KIOSKS[0], KIOSKS[1] + 1))
    prepare(land)
    prepare(blocks)
    P = site.props
    lim = PLAY_HALF_M - 2.0
    placed = []

    def put(spots):
        for px, py, rot in spots:
            if len(placed) >= want:
                return
            if any(np.hypot(px - qx, py - qy) < KIOSK_SPACING_M for qx, qy in placed):
                continue
            ruin = ruins.state_at(px, py, 0) >= ruins.GUTTED
            v, size = district_life.variant_of("hut", "kiosk", ruin)
            foot = Point(px, py).buffer(max(size) / 2 + 0.4)
            if v < 0 or abs(px) > lim or abs(py) > lim or not land.contains(foot) or \
                    blocks.intersects(foot.buffer(2.0)):
                continue
            if (lanes is not None and lanes.intersects(foot)) or not P.clear_of(px, py, max(size) / 2 + 0.5):
                continue
            P.add("hut", px, py, rot, size, v)
            placed.append((px, py))

    put([mouths[i] for i in rng.permutation(len(mouths))])
    if len(placed) < want:
        put(edge_spots(site, land, rng))
    return len(placed)


def cut_to(B, keep):
    """Empties a Batch and returns its triangles (world), greys and alphas
    ((n, 3) each) cut to keep, in their order: a triangle inside keep stays
    as it is, one across its edge becomes the triangles of its part inside
    (with the grey and alpha of its first corner), one outside is dropped."""
    tris = np.asarray(B.t, float).reshape(-1, 3, 2)
    grey = np.asarray(B.g, float).reshape(-1, 3)
    alpha = np.asarray(B.a, float).reshape(-1, 3)
    B.t, B.g, B.a, B.h = [], [], [], []
    if not len(tris):
        return tris, grey, alpha
    polys = shapely.polygons(np.concatenate([tris, tris[:, :1]], 1))
    prepare(keep)
    inside = shapely.contains(keep, polys)
    if inside.all():
        return tris, grey, alpha
    across = ~inside & shapely.intersects(keep, polys)
    out_t, out_g, out_a = [], [], []
    for i in range(len(tris)):
        if inside[i]:
            out_t.append(tris[i:i + 1])
            out_g.append(grey[i:i + 1])
            out_a.append(alpha[i:i + 1])
        elif across[i]:
            t = style.triangulate(polys[i].intersection(keep))
            if len(t):
                out_t.append(t)
                out_g.append(np.full((len(t), 3), grey[i, 0]))
                out_a.append(np.full((len(t), 3), alpha[i, 0]))
    if not out_t:
        return np.zeros((0, 3, 2)), np.zeros((0, 3)), np.zeros((0, 3))
    return np.concatenate(out_t), np.concatenate(out_g), np.concatenate(out_a)


def grounds_drawer(land, blocks, F, rows, lanes, d, seed):
    """Draws an estate piece's grounds: worn ground over its land outside the
    estate's blocks (blocks: those of all its pieces, as one piece's land
    can reach round another's blocks), worn patches (fans) that fit in that
    open ground, lanes and paths (out to the street), entrance paths to the
    stair cores; all of it cut to that open ground, so none of it reaches
    the roads or the buildings left round the estate."""
    open_land = land.difference(unary_union(blocks))
    edge = open_land.boundary

    def draw(L):
        rng = np.random.default_rng(seed)
        B = style.Batch(F.c, F.ang)
        L.fill("groundlines", open_land, WORN_V, 0.35)
        prepare(open_land)
        x0, y0, x1, y1 = F.local(land).bounds
        for _ in range(int(land.area // 900)):
            x = rng.uniform(x0, x1)
            y = rng.uniform(y0, y1)
            c = Point(F.pt(x, y))
            if not open_land.contains(c):
                continue
            r = min(rng.uniform(3.0, 7.0), edge.distance(c))
            if r < PATCH_MIN_M:
                continue
            B.disc(x, y, r, rng.choice([0.05, 0.2]), 10, rng.uniform(0.08, 0.18))
        for kind, a, ya, b, yb, _ in lanes:
            v = LANE_V if kind == "lane" else PAVE_V
            B.rect(a, ya, b, yb, v, 0.95)
            B.line(a, ya, b, ya, 0.12, v * 1.45, 0.8)
            B.line(a, yb, b, yb, 0.12, v * 1.45, 0.8)
        open_m = (d["gap"] - d["wing"]) / 2
        for y, row in rows:
            for cx, cy, poly in row:
                for xc in core_xs(d):
                    yf = cy - d["depth"] / 2
                    ye = yf - (open_m if y != rows[0][0] else SETBACK_M + 1.0)
                    B.rect(cx + xc - 1.0, ye, cx + xc + 1.0, yf, PAVE_V * 0.95, 0.9)
                hl = d["length"] / 2
                B.rect(cx - hl - 1.2, cy - d["depth"] / 2 - 1.2, cx + hl + 1.2, cy - d["depth"] / 2, PAVE_V * 0.8,
                       0.7)
        tris, grey, alpha = cut_to(B, open_land)
        L.add_tris("groundlines", tris, 0.0, va=alpha, vg=grey)
        style.KIT_TRIS["estate_grounds"] = style.KIT_TRIS.get("estate_grounds", 0) + len(tris)
    return draw


def shade_dir(ang_deg):
    a = np.radians(ang_deg)
    lx, ly = style.ROOF_LIGHT
    return float(-lx * np.cos(a) - ly * np.sin(a)), float(lx * np.sin(a) - ly * np.cos(a))


def draw_block(L, b, rng, salvage):
    """An estate block in every ruin state: halo, interior and roof as for
    any building, with the estate's own interior and roof."""
    if b.state == bl.COLLAPSED:
        ruins.draw_collapsed(L, b, rng, salvage)
        return
    d = b.opts["design"]
    style.draw_halo(L, b.poly, 2.6 + 0.35 * d["floors"])
    block_interior(L, b)
    if b.state == bl.INTACT:
        block_roof(L, b, rng)
    else:
        ruins.draw_ruined_roof(L, b, rng, block_roof, False)


def block_interior(L, b):
    """Flats either side of each stair core, a spine wall with doors, the
    stairwells at the front."""
    d = b.opts["design"]
    cx, cy, ang = b.opts["frame"]
    key = style.chunk_key(b.poly)
    L.fill("interiors", b.poly, 0.03, chunk=key)
    room = b.poly.buffer(-0.35, join_style="mitre")
    L.fill("interiors", room, 0.19, chunk=key)
    B = style.Batch((cx, cy), ang)
    hl, hd = d["length"] / 2, d["depth"] / 2
    flat = d["core_step"] / 2
    for k in range(1, int(d["length"] // flat)):
        x = -hl + 1.0 + flat * k
        if x >= hl - 0.5:
            break
        B.line(x, -hd, x, hd - 2.2, 0.24, 0.03)
        B.line(x, hd - 1.2, x, hd, 0.24, 0.03)
    y_spine = hd * 0.15
    x = -hl
    while x < hl:
        B.line(x, y_spine, min(x + flat - 1.3, hl), y_spine, 0.2, 0.03)
        x += flat
    for xc in core_xs(d):
        B.rect(xc - 1.3, -hd + 0.35, xc + 1.3, -hd + 5.2, 0.07)
        for t in np.arange(-hd + 0.9, -hd + 5.0, 0.55):
            B.line(xc - 1.2, t, xc + 1.2, t, 0.06, 0.15)
        B.line(xc, -hd + 0.4, xc, -hd + 5.1, 0.1, 0.03)
    if d["shape"] != "slab":
        ww, w = d["wing_w"], d["wing"]
        for sgn in ((1,) if d["shape"] == "L" else (1, -1)):
            xm = sgn * (hl - ww / 2)
            B.line(xm - ww / 2, hd + w / 2, xm + ww / 2, hd + w / 2, 0.2, 0.03)
    style.KIT_TRIS["estate_blocks"] = style.KIT_TRIS.get("estate_blocks", 0) + B.flush(L, "interiors", key)
    for g in style.polys(room):
        L.strip("interiors", g.exterior if g.exterior.is_ccw else LineString(g.exterior.coords[::-1]), 1.4, +1,
                0.7, 0.0, chunk=key)


def block_roof(L, b, rng):
    """The estate's roof: the parapet, a stair head over each core with the
    estate's water tanks beside it (the same on every block), then dish rows,
    perhaps a shack or a pigeon tower (these vary)."""
    d = b.opts["design"]
    cx, cy, ang = b.opts["frame"]
    v = style.roof_value(b.mv)
    R = style.Roof(L, b.poly, v, rng)
    R.fill(b.poly, v)
    inner = style.set_inner(R, b.poly, 0.5)
    R.shade_in(inner, 1.2, 0.4)
    R.ring(inner, style.PARAPET_W, style.PARAPET_V)
    if b.state != bl.GUTTED:
        B = style.Batch((cx, cy), ang)
        sx, sy = shade_dir(ang)
        hd = d["depth"] / 2

        def free(x0, y0, x1, y1, grow):
            """Takes a local rectangle on the roof (grown by grow, which
            later items keep out of) unless it meets something taken (a
            roof hole on a damaged block)."""
            if any(Polygon(B.world([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])).intersects(t) for t in R.taken):
                return False
            R.taken.append(Polygon(B.world([(x0 - grow, y0 - grow), (x1 + grow, y0 - grow), (x1 + grow, y1 + grow),
                                            (x0 - grow, y1 + grow)])))
            return True

        for xc in core_xs(d):
            x0, y0, x1, y1 = xc - 1.5, -hd + 1.0, xc + 1.5, -hd + 3.8
            if free(x0, y0, x1, y1, 0.3):
                B.rect(x0 + sx * 0.9, y0 + sy * 0.9, x1 + sx * 0.9, y1 + sy * 0.9, 0.0, 0.45)
                B.rect(x0, y0, x1, y1, min(v * 1.6, 0.14))
                B.rect(x0 + 0.15, y0 + 0.15, x1 - 0.15, y1 - 0.15, min(v * 1.3, 0.12))
                B.rect(xc - 0.6, y0 - 0.12, xc + 0.6, y0 + 0.1, 0.015)
            if d["tanks"] == "stand":
                tx0, ty0 = xc + 2.0, -hd + 1.0
                if free(tx0, ty0, tx0 + 2.9, ty0 + 1.6, 0.3):
                    B.rect(tx0 + sx * 1.6, ty0 + sy * 1.6, tx0 + 2.9 + sx * 1.6, ty0 + 1.6 + sy * 1.6, 0.0, 0.4)
                    B.rect(tx0, ty0, tx0 + 2.9, ty0 + 1.6, 0.13)
                    for i in range(2):
                        style.tank_discs(B, tx0 + 0.75 + i * 1.4, ty0 + 0.8, 0.62)
            else:
                ty = hd - 1.4
                if free(xc - 2.2, ty - 0.6, xc + 2.2, ty + 0.6, 0.3):
                    B.line(xc - 2.0, ty, xc + 2.0, ty, 0.12, 0.012)
                    for i in range(3):
                        style.tank_discs(B, xc - 1.6 + i * 1.6, ty, 0.6)
        style.KIT_TRIS["estate_roofs"] = style.KIT_TRIS.get("estate_roofs", 0) + B.flush(L, "roofs", R.key)
        for _ in range(int(rng.integers(1, 4))):
            style.item_dish_row(R, 1.0)
        if rng.random() < d["shack"]:
            style.item_shack(R, 1.0)
        if rng.random() < d["pigeons"]:
            style.item_pigeon_tower(R, 1.0)
    R.ring(b.poly, style.OUTLINE_W, style.OUTLINE_V)
    return R
