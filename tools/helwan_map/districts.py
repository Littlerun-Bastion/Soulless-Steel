"""Tags every part of the map with a district: residential, industrial,
market or farmland. Every other layer reads its densities and rules from the
district (what is built in a street block, which salvage sources go where,
how much ruin).

The map is a grid of CELL_M cells. For each cell:

1. OSM tags, where they exist: landuse (industrial, retail, commercial,
   residential, farmland, farmyard ...) and building tags (industrial,
   warehouse, retail, farm, barn ...).
2. Where there are no tags, building statistics and the reference image:
   - industrial: large plain footprints (over BIG_PLAIN_M2, nearly
     rectangular) cover more than INDUSTRIAL_COVER of the cells round it;
   - market: dense housing along main roads. The generated houses are the
     same size everywhere, so the statistic is street density times housing
     cover beside a main road; the best places (MARKET_SEEDS, at least
     MARKET_SPACING_M apart) grow along their main road into market strips
     about MARKET_LENGTH_M long;
   - farmland: few buildings (cover under FARM_MAX_COVER), mostly open ground,
     and green in the reference image (old fields; bare desert is not
     farmland);
   - else residential.
3. A majority filter (MAJORITY_PASSES passes over the 3 x 3 neighbours) makes
   solid areas with no speckle, then areas smaller than MIN_AREA_M2 join the
   district round them.
4. DistrictZone polygons painted in the master scene win over all of this.

districts.bin: int32 width w, int32 height h, float32 origin x, float32
origin y, float32 cell size (px), then w x h uint8 codes, row by row (world
px). The codes match the game's MapDistricts enum.
"""
import struct

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from shapely.geometry import Point, Polygon
from shapely.ops import substring

from frame import FIT_SPAN_M, MAP_M, PX_PER_M, SCALE, image_path, m_to_world
from gen_city import to_frame_m
from zones import HOUSING, OPEN, WATER

RESIDENTIAL, INDUSTRIAL, MARKET, FARMLAND = 0, 1, 2, 3
NAMES = ["residential", "industrial", "market", "farmland"]
CELL_M = 25.0

LANDUSE = {
    "industrial": INDUSTRIAL, "quarry": INDUSTRIAL, "landfill": INDUSTRIAL, "railway": INDUSTRIAL,
    "retail": MARKET, "commercial": MARKET,
    "residential": RESIDENTIAL,
    "farmland": FARMLAND, "farmyard": FARMLAND, "meadow": FARMLAND, "orchard": FARMLAND,
    "plant_nursery": FARMLAND, "greenhouse_horticulture": FARMLAND, "allotments": FARMLAND,
}
BUILDING = {
    "industrial": INDUSTRIAL, "warehouse": INDUSTRIAL, "factory": INDUSTRIAL, "manufacture": INDUSTRIAL,
    "hangar": INDUSTRIAL, "storage_tank": INDUSTRIAL, "silo": INDUSTRIAL,
    "retail": MARKET, "commercial": MARKET, "kiosk": MARKET, "supermarket": MARKET, "marketplace": MARKET,
    "farm": FARMLAND, "barn": FARMLAND, "farm_auxiliary": FARMLAND, "greenhouse": FARMLAND,
    "cowshed": FARMLAND, "stable": FARMLAND,
}
MAIN_ROADS = {"trunk", "secondary", "tertiary"}

## Footprints larger than this (m2) and nearly rectangular count as large
## plain footprints.
BIG_PLAIN_M2 = 1200.0
## Share of the land round a cell (gaussian, INDUSTRIAL_SIGMA_M) covered by
## large plain footprints above which the cell is industrial.
INDUSTRIAL_COVER = 0.07
INDUSTRIAL_SIGMA_M = 100.0
## Farmland: building cover below this round the cell (gaussian 50 m) ...
FARM_MAX_COVER = 0.05
## ... and greenness (2G - R - B of the reference image, 60 m mean) above this.
FARM_GREEN = -0.012
## Market strips: how many, how far apart, how long along their main road,
## and how far from it.
MARKET_SEEDS = 9
MARKET_SPACING_M = 650.0
MARKET_LENGTH_M = 450.0
MARKET_DEPTH_M = 70.0
MAJORITY_PASSES = 3
MIN_AREA_M2 = 12000.0


class Districts:
    def __init__(self, codes, half_m):
        self.codes = codes
        self.half_m = half_m
        self.n = codes.shape[0]

    def ij(self, x, y):
        i = np.clip(((np.asarray(y) + self.half_m) / CELL_M).astype(int), 0, self.n - 1)
        j = np.clip(((np.asarray(x) + self.half_m) / CELL_M).astype(int), 0, self.n - 1)
        return i, j

    def at(self, x, y):
        return self.codes[self.ij(x, y)]

    def of_geom(self, g):
        p = g.representative_point()
        return int(self.at(p.x, p.y))

    def share(self, geom, code):
        """Share of the cells under a polygon's bounding box that have code."""
        x0, y0, x1, y1 = geom.bounds
        i0, j0 = self.ij(x0, y0)
        i1, j1 = self.ij(x1, y1)
        win = self.codes[i0:i1 + 1, j0:j1 + 1]
        return float((win == code).mean()) if win.size else 0.0

    def counts(self):
        return {NAMES[c]: int((self.codes == c).sum()) for c in range(len(NAMES))}

    def write(self, path):
        h, w = self.codes.shape
        with open(path, "wb") as fh:
            fh.write(struct.pack("<iifff", w, h, -self.half_m * PX_PER_M, -self.half_m * PX_PER_M, CELL_M * PX_PER_M))
            fh.write(self.codes.astype(np.uint8).tobytes())


def _raster(n, half_m, polys, values=None, base=0, dtype=np.uint8):
    """Polygons (map-frame metres) burnt into an n x n grid of CELL_M cells."""
    im = Image.new("I", (n, n), base)
    d = ImageDraw.Draw(im)
    k = 1.0 / CELL_M
    for idx, g in enumerate(polys):
        v = 1 if values is None else values[idx]
        for p in getattr(g, "geoms", [g]):
            if p.geom_type != "Polygon" or p.is_empty:
                continue
            d.polygon([((x + half_m) * k, (y + half_m) * k) for x, y in p.exterior.coords], fill=int(v))
    return np.asarray(im).astype(dtype)


def greenness(n, half_m):
    """2G - R - B of the reference image, averaged over CELL_M cells."""
    img = np.asarray(Image.open(image_path()).convert("RGB")).astype(np.float32) / 255
    exg = 2 * img[..., 1] - img[..., 0] - img[..., 2]
    h, w = exg.shape
    c = (np.arange(n) + 0.5) / n * 2 * half_m - half_m
    gx = c / SCALE * w / FIT_SPAN_M + w / 2 - 0.5
    gy = c / SCALE * h / FIT_SPAN_M + h / 2 - 0.5
    yy, xx = np.meshgrid(gy, gx, indexing="ij")
    exg = ndi.gaussian_filter(exg, 1.0)
    return ndi.map_coordinates(exg, [yy, xx], order=1, mode="nearest")


def tag_cells(feats, n, half_m):
    """Codes from OSM tags (-1 where there is no tag)."""
    polys, vals = [], []
    for kind, rings, p in feats:
        if kind != "poly":
            continue
        code = None
        if p.get("landuse") in LANDUSE:
            code = LANDUSE[p["landuse"]]
        elif p.get("building") in BUILDING:
            code = BUILDING[p["building"]]
        elif p.get("amenity") == "marketplace":
            code = MARKET
        if code is None:
            continue
        g = Polygon(to_frame_m(rings[0])).buffer(0)
        if g.is_empty:
            continue
        # Large landuse areas first, so building tags inside them win.
        polys.append((-g.area if "landuse" in p else 0.0, g, code))
    polys.sort(key=lambda t: t[0])
    return _raster(n, half_m, [g for _, g, _ in polys], [c + 1 for _, _, c in polys]).astype(np.int16) - 1


def _cell_sums(n, half_m, pts, weights):
    out = np.zeros((n, n))
    if len(pts) == 0:
        return out
    i = np.clip(((pts[:, 1] + half_m) / CELL_M).astype(int), 0, n - 1)
    j = np.clip(((pts[:, 0] + half_m) / CELL_M).astype(int), 0, n - 1)
    np.add.at(out, (i, j), weights)
    return out


def majority(codes, passes):
    """Each cell takes the most common code of its 3 x 3 neighbourhood (ties
    keep the cell's own code)."""
    k = len(NAMES)
    for _ in range(passes):
        votes = np.stack([ndi.uniform_filter((codes == c).astype(np.float32), 3, mode="nearest") for c in range(k)])
        best = votes.argmax(0)
        top = votes.max(0)
        own = np.take_along_axis(votes, codes[None].astype(np.int64), 0)[0]
        codes = np.where(own >= top - 1e-6, codes, best).astype(np.uint8)
    return codes


def drop_small(codes, min_cells):
    """Areas smaller than min_cells take the code most common round them."""
    for c in range(len(NAMES)):
        lab, m = ndi.label(codes == c)
        if m == 0:
            continue
        sizes = ndi.sum(np.ones_like(lab), lab, range(1, m + 1))
        for idx in np.flatnonzero(sizes < min_cells) + 1:
            sel = lab == idx
            ring = ndi.binary_dilation(sel, iterations=1) & ~sel
            if not ring.any():
                continue
            vals = np.bincount(codes[ring], minlength=len(NAMES))
            vals[c] = 0
            codes[sel] = int(vals.argmax())
    return codes


def market_strips(n, half_m, roads, housing_cover, dens_cells, rng):
    """Cells of the market strips: the best places by street density times
    housing cover beside a main road, grown along that road."""
    mains = [(line, w) for _, _, w, _, kind, line in roads if kind in MAIN_ROADS and line is not None]
    if not mains:
        return np.zeros((n, n), bool)
    road_mask = _raster(n, half_m, [l.buffer(w / 2 + MARKET_DEPTH_M * 0.5) for l, w in mains]) > 0
    score = ndi.gaussian_filter(housing_cover * dens_cells, 3) * road_mask
    out = np.zeros((n, n), bool)
    seeds = []
    order = np.argsort(score.ravel())[::-1]
    lim = half_m * 0.9
    for idx in order:
        if len(seeds) >= MARKET_SEEDS or score.ravel()[idx] <= 0:
            break
        i, j = divmod(int(idx), n)
        x, y = (j + 0.5) * CELL_M - half_m, (i + 0.5) * CELL_M - half_m
        if abs(x) > lim or abs(y) > lim:
            continue
        if any(np.hypot(x - sx, y - sy) < MARKET_SPACING_M for sx, sy in seeds):
            continue
        seeds.append((x, y))
        p = Point(x, y)
        line, w = min(mains, key=lambda lw: lw[0].distance(p))
        d = line.project(p)
        half = MARKET_LENGTH_M * rng.uniform(0.4, 0.6)
        part = substring(line, max(0.0, d - half), min(line.length, d + half))
        strip = part.buffer(w / 2 + MARKET_DEPTH_M, cap_style="flat")
        out |= _raster(n, half_m, [strip]) > 0
    return out


def build(feats, f, zone, roads, buildings, painted=(), seed=17):
    """buildings: footprints (map-frame metres). painted: (polygon, name)
    DistrictZone overrides from the master scene, in scene order."""
    rng = np.random.default_rng(seed)
    half_m = MAP_M / 2
    n = int(round(MAP_M / CELL_M))
    cell_a = CELL_M * CELL_M

    tags = tag_cells(feats, n, half_m)

    cen = np.array([[g.centroid.x, g.centroid.y] for g in buildings]) if buildings else np.zeros((0, 2))
    area = np.array([g.area for g in buildings])
    fill = np.array([g.area / max(g.minimum_rotated_rectangle.area, 1e-6) for g in buildings])
    plain = (area >= BIG_PLAIN_M2) & (fill >= 0.8)
    cover = _cell_sums(n, half_m, cen, area) / cell_a
    big_cover = _cell_sums(n, half_m, cen[plain], area[plain]) / cell_a
    cover_s = ndi.gaussian_filter(cover, 50.0 / CELL_M)
    big_s = ndi.gaussian_filter(big_cover, INDUSTRIAL_SIGMA_M / CELL_M)

    zk = zone.shape[0] // n
    zc = zone[: n * zk, : n * zk].reshape(n, zk, n, zk)
    open_share = (zc == OPEN).mean((1, 3))
    housing_share = (zc == HOUSING).mean((1, 3))
    water_share = (zc == WATER).mean((1, 3))
    dk = f["dens"].shape[0] // n
    dens_cells = f["dens"][: n * dk, : n * dk].reshape(n, dk, n, dk).mean((1, 3))
    green = ndi.uniform_filter(greenness(n, half_m), int(round(60.0 / CELL_M)) | 1)

    codes = np.full((n, n), RESIDENTIAL, np.uint8)
    farm = (cover_s < FARM_MAX_COVER) & (open_share > 0.6) & (green > FARM_GREEN) & (water_share < 0.5)
    codes[farm] = FARMLAND
    codes[market_strips(n, half_m, roads, housing_share, dens_cells, rng) & (housing_share > 0.3)] = MARKET
    codes[big_s > INDUSTRIAL_COVER] = INDUSTRIAL
    codes = np.where(tags >= 0, tags, codes).astype(np.uint8)

    codes = majority(codes, MAJORITY_PASSES)
    codes = drop_small(codes, int(MIN_AREA_M2 / cell_a))

    if painted:
        polys = [p for p, _ in painted]
        vals = [NAMES.index(name) + 1 if name in NAMES else RESIDENTIAL + 1 for _, name in painted]
        over = _raster(n, half_m, polys, vals)
        codes = np.where(over > 0, over.astype(np.int16) - 1, codes).astype(np.uint8)
    return Districts(codes, half_m)
