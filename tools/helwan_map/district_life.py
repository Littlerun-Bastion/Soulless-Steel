"""Small things for the residential, market and farmland districts (the
big-medium-small rule of the industrial density brief, applied to the rest
of the city). The houses, halls and farm buildings are the big and medium
things; this pass adds the small ones as props, grouped where people leave
things: against house walls, at street corners, round market stalls, in
farmyards and at field corners. Rooftop detail (water tanks, stair heads,
roof rooms, satellite dishes) is drawn with the roofs (style.py).

- Wall clutter: rubbish heaps, tyres, crates, gensets, washing lines on
  free ground next to a building wall, off the road (props of kind
  "clutter": sprites, no body).
- Lean-tos and sheds against house walls, kiosks at street corners (props
  of kind "hut": they break like market stalls; one where a building would
  be gutted or collapsed is a ruin from the start).
- Trees in residential courtyards.
- Market: more stalls in the gaps beside the stalls, and crates, sacks and
  tarps round them; kiosks at the corners.
- Farmland: field huts and haystacks at field edges, carts near the farm
  buildings, palm rows along the farm tracks.

Nothing here is an obstacle or a building. The chances per candidate spot
(*_CHANCE) set how many there are; the spots are on the props' 1 m grid
(props.Space), sampled every SAMPLE_M.
"""
import numpy as np

import props
import ruins

## Candidate spots are taken on this grid (m).
SAMPLE_M = 3
## Wall spots: free ground within WALL_M of a building and at least ROOM_M
## from anything solid.
WALL_M = 1.6
ROOM_M = 0.9
## Chance that a wall spot gets a clutter group, per district (residential,
## industrial, market, farmland).
CLUTTER_CHANCE = (0.22, 0.0, 0.4, 0.15)
## Chance that a wall spot with room for it gets a lean-to or shed.
SHED_CHANCE = (0.02, 0.0, 0.01, 0.03)
## Chance that a street corner gets a kiosk (residential, market).
KIOSK_CHANCE = (0.25, 0.0, 0.5, 0.0)
## Courtyard trees: chance per spot 2 to 5 m from a building with room.
TREE_CHANCE = 0.012
## Market: extra stalls next to a stall, goods round a stall.
EXTRA_STALL_CHANCE = 0.35
GOODS_CHANCE = 0.6
## Farmland: open spots (at least FIELD_ROOM_M from anything solid).
FIELD_ROOM_M = 5.0
FIELD_HUT_CHANCE = 0.01
HAYSTACK_CHANCE = 0.03
CART_CHANCE = 0.1
## Palm rows along farm tracks: spacing (m) and chance per spot.
PALM_STEP_M = 7.0
PALM_CHANCE = 0.4

RESIDENTIAL, INDUSTRIAL, MARKET, FARMLAND = 0, 1, 2, 3
WALL_CLUTTER = {
    RESIDENTIAL: ["rubbish", "tyres", "crates", "genset", "washing", "drums", "tarp"],
    MARKET: ["crates", "sacks", "tarp", "rubbish", "cart"],
    FARMLAND: ["sacks", "tyres", "drums", "cart", "rubbish"],
}
GOODS = ["crates", "sacks", "tarp", "crates", "sacks"]


def variant_of(kind, name, ruin=False):
    """Index and (length, width) of a hut, clutter or stall sprite by name."""
    file = f"{kind}_{name}{'_broken' if ruin else ''}.png"
    for v, e in enumerate(props.CATALOGUE.get(kind, [])):
        if e["file"] == file:
            return v, (e["length_m"], e["width_m"])
    return -1, props.SIZE_M[kind]


def wall_angle(S, x, y):
    """The direction along the nearest building wall at (x, y), from the
    distance grid's slope."""
    i, j = S.ij(x, y)
    n = S.n
    d = S.bld_dist
    gx = float(d[i, min(j + 1, n - 1)]) - float(d[i, max(j - 1, 0)])
    gy = float(d[min(i + 1, n - 1), j]) - float(d[max(i - 1, 0), j])
    return float(np.arctan2(gy, gx)) + np.pi / 2


class Life:
    def __init__(self, P, S, D, rng):
        self.P, self.S, self.D, self.rng = P, S, D, rng
        self.made = {"clutter": 0, "huts": 0, "huts_ruined": 0, "stalls": 0, "trees": 0}

    def district(self, x, y):
        return int(self.D.at(x, y))

    def prop(self, kind, name, x, y, rot, clear=0.4):
        ruin = False
        if kind == "hut":
            ruin = ruins.state_at(x, y, self.district(x, y)) >= ruins.GUTTED
        v, size = variant_of(kind, name, ruin)
        if v < 0 or self.S.room(x, y) < min(size) / 2 or not self.P.clear_of(x, y, max(size) / 2 + clear):
            return False
        if not self.P.add(kind, x, y, rot, size, v):
            return False
        if kind == "hut":
            self.made["huts"] += 1
            self.made["huts_ruined"] += ruin
        else:
            self.made["clutter" if kind == "clutter" else "stalls"] += 1
        return True

    def group(self, names, x, y, ang, n):
        rng = self.rng
        for _ in range(n):
            px, py = x + rng.normal(0, 1.0), y + rng.normal(0, 1.0)
            self.prop("clutter", str(rng.choice(names)), px, py, ang + rng.choice([0, np.pi / 2]) + rng.normal(0, 0.1),
                      clear=0.2)

    def walls(self):
        """Clutter groups and sheds against building walls."""
        S, rng = self.S, self.rng
        near = (~S.solid & (S.bld_dist <= WALL_M) & (S.free_dist >= ROOM_M))[::SAMPLE_M, ::SAMPLE_M]
        ii, jj = np.nonzero(near)
        for k in rng.permutation(len(ii)):
            x = (jj[k] * SAMPLE_M + 0.5) * props.GRID_M - props.HALF_M
            y = (ii[k] * SAMPLE_M + 0.5) * props.GRID_M - props.HALF_M
            d = self.district(x, y)
            if d == INDUSTRIAL or d >= len(CLUTTER_CHANCE):
                continue
            roll = rng.random()
            ang = wall_angle(S, x, y)
            if roll < SHED_CHANCE[d] and S.room(x, y) >= 1.6:
                # The shed's back against the wall.
                nx, ny = np.cos(ang - np.pi / 2), np.sin(ang - np.pi / 2)
                self.prop("hut", "shed", x + nx * 0.5, y + ny * 0.5, ang)
            elif roll < SHED_CHANCE[d] + CLUTTER_CHANCE[d]:
                self.group(WALL_CLUTTER[d], x, y, ang, int(rng.integers(1, 4)))

    def corners(self, junctions):
        """Kiosks at street corners."""
        S, rng = self.S, self.rng
        for x, y in junctions:
            d = self.district(x, y)
            if d >= len(KIOSK_CHANCE) or rng.random() > KIOSK_CHANCE[d]:
                continue
            for _ in range(8):
                a = rng.uniform(0, 2 * np.pi)
                r = rng.uniform(6.0, 11.0)
                px, py = x + np.cos(a) * r, y + np.sin(a) * r
                if not S.road[S.ij(px, py)] and S.room(px, py) >= 1.4 and S.bld_dist[S.ij(px, py)] <= 4.0:
                    if self.prop("hut", "kiosk", px, py, wall_angle(S, px, py)):
                        break

    def courtyards(self):
        S, rng = self.S, self.rng
        spots = (~S.solid & (S.bld_dist >= 2.0) & (S.bld_dist <= 5.0) & (S.free_dist >= 2.5))[::SAMPLE_M, ::SAMPLE_M]
        ii, jj = np.nonzero(spots)
        for k in rng.permutation(len(ii)):
            if rng.random() > TREE_CHANCE:
                continue
            x = (jj[k] * SAMPLE_M + 0.5) * props.GRID_M - props.HALF_M
            y = (ii[k] * SAMPLE_M + 0.5) * props.GRID_M - props.HALF_M
            if self.district(x, y) != RESIDENTIAL:
                continue
            before = len(self.P.items)
            props.add_tree(self.P, S, x, y, rng.uniform(6.0, 10.0), rng)
            self.made["trees"] += len(self.P.items) - before

    def market(self):
        """More stalls beside the market's stalls, and goods round them."""
        rng = self.rng
        stall = props.KINDS.index("stall")
        cat = props.CATALOGUE.get("stall", [])
        for it in [it for it in self.P.items if it[0] == stall]:
            _, x, y, rot, sx, sy, v = it
            ax, ay = np.cos(rot), np.sin(rot)
            if rng.random() < EXTRA_STALL_CHANCE and cat:
                w = int(rng.integers(len(cat)))
                size = (cat[w]["length_m"], cat[w]["width_m"])
                for side in rng.permutation([-1.0, 1.0]):
                    px, py = x + ax * side * (sx / 2 + size[0] / 2 + 0.6), y + ay * side * (sx / 2 + size[0] / 2 + 0.6)
                    if self.S.room(px, py) >= size[1] / 2 and self.P.clear_of(px, py, max(size) / 2 + 0.2) and \
                            self.P.add("stall", px, py, rot + rng.normal(0, 0.05), size, w):
                        self.made["stalls"] += 1
                        break
            if rng.random() < GOODS_CHANCE:
                bx, by = -ay, ax
                gx, gy = x - bx * (sy / 2 + 1.0), y - by * (sy / 2 + 1.0)
                self.group(GOODS, gx, gy, rot, int(rng.integers(1, 3)))

    def farmland(self, tracks):
        """Field huts, haystacks and carts, and palm rows along farm tracks."""
        S, rng = self.S, self.rng
        spots = (~S.solid & (S.free_dist >= FIELD_ROOM_M))[::SAMPLE_M * 2, ::SAMPLE_M * 2]
        ii, jj = np.nonzero(spots)
        for k in rng.permutation(len(ii)):
            x = (jj[k] * SAMPLE_M * 2 + 0.5) * props.GRID_M - props.HALF_M
            y = (ii[k] * SAMPLE_M * 2 + 0.5) * props.GRID_M - props.HALF_M
            if self.district(x, y) != FARMLAND:
                continue
            roll = rng.random()
            if roll < FIELD_HUT_CHANCE:
                self.prop("hut", str(rng.choice(["shed", "shelter"])), x, y, rng.uniform(0, np.pi))
            elif roll < FIELD_HUT_CHANCE + HAYSTACK_CHANCE:
                for _ in range(int(rng.integers(1, 4))):
                    self.prop("clutter", "haystack", x + rng.normal(0, 2.5), y + rng.normal(0, 2.5), rng.uniform(0, 6.28))
        near = (~S.solid & (S.bld_dist <= 6.0) & (S.free_dist >= 2.0))[::SAMPLE_M, ::SAMPLE_M]
        ii, jj = np.nonzero(near)
        for k in rng.permutation(len(ii)):
            if rng.random() > CART_CHANCE:
                continue
            x = (jj[k] * SAMPLE_M + 0.5) * props.GRID_M - props.HALF_M
            y = (ii[k] * SAMPLE_M + 0.5) * props.GRID_M - props.HALF_M
            if self.district(x, y) == FARMLAND:
                self.prop("clutter", "cart", x, y, wall_angle(S, x, y))
        for line, w in tracks:
            for side in (-1, 1):
                edge = line.offset_curve(side * (w / 2 + 2.5))
                for seg in getattr(edge, "geoms", [edge]):
                    if seg.geom_type != "LineString":
                        continue
                    for dist in np.arange(rng.uniform(0, PALM_STEP_M), seg.length, PALM_STEP_M):
                        p = seg.interpolate(dist)
                        if rng.random() < PALM_CHANCE and self.district(p.x, p.y) == FARMLAND:
                            before = len(self.P.items)
                            props.add_tree(self.P, S, p.x, p.y, rng.uniform(7.0, 10.0), rng)
                            self.made["trees"] += len(self.P.items) - before


def place(P, S, D, roads, junctions, rng):
    """Adds the small things of the residential, market and farmland
    districts. Returns what it made."""
    L = Life(P, S, D, rng)
    L.market()
    L.corners([(float(x), float(y)) for x, y in junctions[:, :2]] if len(junctions) else [])
    L.walls()
    L.courtyards()
    tracks = [(line, w) for _, _, w, _, kind, line in roads
              if line is not None and kind in ("track", "unclassified", "service") and int(D.at(*line.interpolate(0.5, normalized=True).coords[0])) == FARMLAND]
    L.farmland(tracks)
    return L.made
