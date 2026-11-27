"""The service sites on frontage lots and house plots (sites.py runs them):
car dealerships, truck repair yards, car parks, bus depots, backstreet
garages and parking in front of large buildings.

Each type has a planner (plan_*: lays a site out on a lot cut from the
block along a road, from sitekit.frontage_lot, or reports that it does not
fit) and a builder (build_*: takes the land, adds the buildings, vehicles,
props and salvage, and a drawer for the ground). Planners see only the
whole map's layout, so the choice of places is the same in a window run as
in a full run; builders run for the places in the window.

  dealerships    DEALERSHIPS on main roads: a showroom (glass front) at the
                 back of the lot, a forecourt of new cars in two rows facing
                 the road and the showroom, a driveway and a pole sign.
  truck yards    TRUCK_YARDS on industrial ground in blocks the industrial
                 module left: a workshop hall with bay doors, trucks nosed to
                 the doors and parked round the yard (tankers and dump
                 trucks only on industrial ground), a fence, a car_parts
                 source by the hall, tyres, drums and engines about.
  car parks      CAR_PARKS surface lots in residential and market streets:
                 rows of bays and aisles (sitekit.bay_grid), CAR_PARK_FULL
                 full with some wrecks, kerbed islands where the rows leave
                 room, a guard hut on the island by the driveway. The lot
                 shrinks to its rows and aisles.
  bus depots     BUS_DEPOTS on main roads: a workshop hall, a row of buses
                 under a canopy (overheads) at the back, a middle row in the
                 open (buses, or minibuses where the lot is shallower) with
                 a lane wide enough for a mecha behind it, a row of
                 minibuses along the front, a gate lane from the road to
                 the back, a wall.
  garages        GARAGES backstreet workshops: a house facing a residential
                 or market street becomes a one-bay workshop (the building
                 kind "garage", a sign board and a wide open bay towards the
                 street); on GARAGE_YARD_SHARE of them the next house along
                 the street is cleared into a walled yard of wrecks and
                 parts. A car or wreck nosed into the bay, tyre stacks, tyres
                 and drums by the wall on both sides of it, cars and wrecks
                 along the kerb beside it, an oil stain and a car_parts
                 source at the bay.
  parking out front
                 strips between a large roof (or a large generated
                 building) and the road in front of it at least FRONT_MIN_M
                 deep and free of houses: FRONT_SHARE of them become bays
                 (straight in, angled where it is shallow, two rows with an
                 aisle where it is deep), FRONT_FULL full.
  side car parks SIDE_PARKS at most, on open ground beside a large building
                 that reaches a road: an aisle along the wall and rows of
                 bays, the ground left over as kerbed islands.
"""
import numpy as np
import shapely
from shapely import STRtree
from shapely.geometry import LineString, Point
from shapely.ops import nearest_points, unary_union

import kit
import sitekit as sk
import style
from districts import INDUSTRIAL, MARKET, RESIDENTIAL


class FrontPlan:
    """A site on a frontage lot: its type, frontage point, lot and the
    pieces its planner laid out (a dict)."""

    def __init__(self, kind, fr, lot, pieces):
        self.kind, self.fr, self.lot, self.pieces = kind, fr, lot, pieces


def frontage_points(ctx, kinds, seed, share=1.0, step=24.0):
    """Points along the block edges that face roads of the given kinds, in
    blocks no district module rebuilds; share of them kept (by a fixed hash
    of the place)."""
    key = (tuple(sorted(kinds)), step)
    if key not in ctx.cache:
        ctx.cache[key] = sk.frontages(ctx.blocks, ctx.R, set(kinds), step=step, area=ctx.inner,
                                      block_ok=lambda b: ctx.block_use(b) is None)
    return [fr for fr in ctx.cache[key] if share >= 1.0 or sk.place_hash(seed, *fr.p) < share]


def pick_sites(ctx, kind, frs, n, spacing, score, plan, seed, tries=500):
    """Chooses up to n sites from frontage points: best score first, at least
    spacing apart, each planned with its own random numbers; a plan that
    fails or overlaps a place already chosen is passed over."""
    scored = []
    for i, fr in enumerate(frs):
        sc = score(fr)
        if sc is not None:
            scored.append((sc + 0.5 * sk.place_hash(seed, *fr.p), i))
    scored.sort(reverse=True)
    chosen, pts = [], []
    for k, (_, i) in enumerate(scored):
        if len(chosen) >= n or k >= tries:
            break
        fr = frs[i]
        if pts and np.min(np.hypot(*(np.asarray(pts) - fr.p).T)) < spacing:
            continue
        got = plan(fr, sk.place_rng(seed + 1, *fr.p))
        if got is None or ctx.mine_hits(got.lot.poly, 4.0) or ctx.blocked(got.lot.poly):
            continue
        chosen.append(got)
        pts.append(fr.p)
        ctx.reserve(got.lot.poly)
    ctx.stats[kind + "_chosen"] = len(chosen)
    return chosen


def front_lot(ctx, fr, length, depth, max_cover=1.0):
    """A frontage lot centred on the frontage point, the large roofs there
    cut out (Ctx.cut_big), or None when the block does not hold it (another
    road, the block's end, large roofs) or it is built up."""
    lot = ctx.cut_big(sk.frontage_lot(fr, ctx.R, length, depth, x0=-length / 2))
    if lot is None or lot.poly.area < 0.82 * length * (depth - sk.ROAD_SETBACK_M):
        return None
    if not ctx.inner.contains(lot.poly):
        return None
    if max_cover < 1.0 and ctx.house_cover(lot.poly) > max_cover:
        return None
    return lot


def settle(ctx, plan, owner):
    """The free part of a planned lot, with its land taken (houses trimmed or
    dropped): the Lot to build on, or None when another module took too
    much of it."""
    site = ctx.site
    free = sk.free_part(site, plan.lot.poly)
    if free is None or free.area < 0.97 * plan.lot.poly.area:
        ctx.count(owner + "_skipped")
        return None
    lot = sk.Lot(free, plan.lot.F, plan.lot.concrete, plan.lot.kind)
    lot, dropped = sk.take_land(site, lot, "sites:" + owner)
    ctx.count("houses_removed", dropped)
    return lot


def parts_source(ctx, x, y, ang, rng, w=2.6, h=1.6):
    """A car_parts salvage source (a parts pile and bench), shown by an
    engine block and a tyre stack, unless a site vehicle stands there. It
    goes down before its site's vehicles: returns its outline grown a
    little, for the site's Parker to keep off, or None."""
    site = ctx.site
    rect = sk.car_rect(x, y, ang, (w, h), 0.2)
    if sk.placed(site).hits(rect) or not site.salvage.add("car_parts", x, y, ang, w, h):
        return None
    c, s = np.cos(ang), np.sin(ang)
    sk.clutter(site, "engine", x - c * 0.6, y - s * 0.6, ang + rng.normal(0, 0.15), clear=-0.5)
    sk.clutter(site, "tyre_stack", x + c * 0.8, y + s * 0.8, ang + rng.normal(0, 0.2), clear=-0.5)
    ctx.count("car_parts")
    return rect


def hut_variant(name, p):
    """A hut sprite by name, its ruin where a building there would be gutted
    or collapsed."""
    import district_life
    import ruins
    ruin = ruins.state_at(p[0], p[1], 0) >= ruins.GUTTED
    return district_life.variant_of("hut", name, ruin)


# ------------------------------------------------------------- dealerships

## Car dealerships: how many, how far apart (m), their lot (m along the
## road, m deep), how full their forecourt is and the cars they sell.
DEALERSHIPS = 4
DEALER_SPACING_M = 700.0
DEALER_LOT_M = ((56.0, 74.0), (36.0, 44.0))
DEALER_FULL = (0.8, 1.0)
DEALER_CARS = ("sports", "suv", "estate", "hatchback")
DEALER_ROADS = {"trunk": 0.7, "secondary": 0.75, "tertiary": 0.45}


def plan_dealer(ctx, fr, rng):
    length, depth = rng.uniform(*DEALER_LOT_M[0]), rng.uniform(*DEALER_LOT_M[1])
    lot = front_lot(ctx, fr, length, depth)
    if lot is None:
        return None
    F = lot.F
    x0, x1, y0, y1 = sk.box_of(F, lot.poly)
    sw = min(rng.uniform(24.0, 32.0), x1 - x0 - 16.0)
    sd = rng.uniform(12.0, 15.0)
    ys = 1.0 + 2.5 + 2 * sk.BAY_D + sk.AISLE_M + 2.0
    if ys + sd > y1 - 1.5 or sw < 16.0:
        return None
    left = rng.random() < 0.5
    sx0 = x1 - 2.0 - sw if left else x0 + 2.0
    room = F.rect(sx0, ys, sx0 + sw, ys + sd)
    if not lot.fits(room, 1.0):
        return None
    dx = x0 + 6.0 if left else x1 - 6.0
    return FrontPlan("dealer", fr, lot, {"showroom": room, "sx": (sx0, sx0 + sw), "ys": ys, "drive_x": dx})


def build_dealer(ctx, plan):
    site = ctx.site
    lot = settle(ctx, plan, "dealer")
    if lot is None:
        return
    F, P = lot.F, plan.pieces
    rng = sk.place_rng(611, *plan.fr.p)
    room = P["showroom"]
    sx0, sx1 = P["sx"]
    sk.building(site, room, "showroom", sk.LFrame(F.pt(sx0, P["ys"]), F.u, F.n), glass_m=rng.uniform(3.0, 4.5))
    x0, x1, y0, y1 = sk.box_of(F, lot.poly)
    yr = 1.0 + 2.5
    court = F.rect(x0 + 1.5, yr, x1 - 1.5, P["ys"] - 0.5).intersection(lot.poly)
    rows = sk.bay_row(F, x0 + 2.0, x1 - 2.0, yr + sk.BAY_D, -1, court.buffer(0.1))
    rows += sk.bay_row(F, x0 + 2.0, x1 - 2.0, yr + sk.BAY_D + sk.AISLE_M, +1, court.buffer(0.1))
    dx = P["drive_x"]
    mouth = sk.mouth(F, dx, 7.0, depth_in=yr + sk.BAY_D + 1.0)
    rows = [b for b in rows if not b.poly().intersects(mouth)]
    # Beside the showroom, a stock yard of cars packed in rows off an aisle
    # along the forecourt.
    back = sk.largest(lot.poly.buffer(-1.5, join_style="mitre").intersection(
        F.rect(x0, P["ys"] - 0.5, x1, y1)).difference(room.buffer(2.5, join_style="mitre")))
    stock, stock_aisles = ([], [])
    if back is not None and back.area > 120:
        stock, stock_aisles = sk.bay_grid(F, back, y_start=P["ys"] - 0.5)
    paved = [court, mouth.intersection(lot.poly), room.buffer(2.0, join_style="mitre")] + \
        [b.poly() for b in stock] + stock_aisles
    apron, islands = sk.shape_ground(lot, paved, [room], [sk.driveway(mouth, lot.poly, lot.concrete)], fillet=2.0)
    park = sk.Parker(site, rng, [room.buffer(0.3)] + [g.buffer(-0.3) for g in style.polys(islands)],
                     ctx.stats.setdefault("vehicles", {}))
    park.fill_bays(rows, rng.uniform(*DEALER_FULL), wreck_share=0.03, reverse_share=0.0, names=DEALER_CARS)
    park.fill_bays(stock, 0.85, wreck_share=0.05, reverse_share=0.5, names=DEALER_CARS)
    rows = rows + stock
    # The pole sign by the road at the end away from the driveway, standing
    # at least 1 m inside the lot (the frame's y = 0 line, the block edge,
    # can run on the road's concrete).
    sign = Point(*F.pt(x0 + 3.0 if dx > (x0 + x1) / 2 else x1 - 3.0, 2.2))
    inner = lot.poly.buffer(-1.0)
    if not inner.is_empty and not inner.contains(sign):
        sign = nearest_points(inner, sign)[0]
    sign = (sign.x, sign.y)
    ctx.count("dealerships")
    ctx.place("dealership", lot.poly)
    seed = int(rng.integers(1 << 30))
    concrete = lot.concrete
    beside = unary_union([b.poly for b in sk.buildings_near(site, lot.poly, 1.0)])

    def draw(L):
        sk.draw_apron(L, apron, concrete, v=0.24, joints=0.0, keep_off=room)
        sk.draw_islands(L, islands)
        sk.lot_wall(L, lot, concrete, keep_off=beside)
        sk.bay_lines(L, rows)
        sk.sign_pole(L, sign[0], sign[1], F.u, np.random.default_rng(seed).uniform(7.0, 9.0), (3.2, 1.6))
    site.drawers.append(draw)


# ------------------------------------------------------------- truck yards

## Truck repair yards on industrial land the industrial module left: how
## many, how far apart (m), their lot (m along the road, m deep), and the
## trucks in them (tankers and dump trucks stand only on industrial ground).
## The STRIPPED trucks are in for repair, drained and stripped: they carry
## no salvage source (their own tables give fuel).
TRUCK_YARDS = 6
TRUCK_SPACING_M = 300.0
TRUCK_LOT_M = ((46.0, 64.0), (34.0, 48.0))
YARD_TRUCKS = ("container_truck", "dump_truck", "tanker", "minibus")
YARD_TRUCK_WEIGHTS = (0.35, 0.3, 0.25, 0.1)
STRIPPED = ("dump_truck", "tanker")


def plan_truck_yard(ctx, fr, rng):
    length, depth = rng.uniform(*TRUCK_LOT_M[0]), rng.uniform(*TRUCK_LOT_M[1])
    lot = front_lot(ctx, fr, length, depth)
    if lot is None or ctx.D.share(lot.poly, INDUSTRIAL) < 0.7:
        return None
    F = lot.F
    x0, x1, y0, y1 = sk.box_of(F, lot.poly)
    hw = min(rng.uniform(22.0, 32.0), x1 - x0 - 6.0)
    hd = rng.uniform(13.0, 17.0)
    hy = y1 - 2.0 - hd
    if hy < 18.0 or hw < 16.0:
        return None
    hx0 = x0 + rng.uniform(2.0, max(2.0, x1 - x0 - hw - 2.0))
    hall = F.rect(hx0, hy, hx0 + hw, hy + hd)
    if not lot.fits(hall, 0.8):
        return None
    return FrontPlan("truck_yard", fr, lot, {"hall": hall, "hx": (hx0, hx0 + hw), "hy": hy})


def pick_truck(park, rng):
    name = str(rng.choice(YARD_TRUCKS, p=np.asarray(YARD_TRUCK_WEIGHTS)))
    got = park.pick("truck", names=(name,))
    return (name,) + got if got is not None else None


def build_truck_yard(ctx, plan):
    site = ctx.site
    lot = settle(ctx, plan, "truck_yard")
    if lot is None:
        return
    F, P = lot.F, plan.pieces
    rng = sk.place_rng(621, *plan.fr.p)
    hall = P["hall"]
    hx0, hx1 = P["hx"]
    doors = [float(x) for x in np.arange(4.5, hx1 - hx0 - 3.0, 7.0)]
    sk.building(site, hall, "workshop_hall", sk.LFrame(F.pt(hx0, P["hy"]), F.u, F.n), doors=doors)
    x0, x1, y0, y1 = sk.box_of(F, lot.poly)
    gate_x = x0 + 7.0 if rng.random() < 0.5 else x1 - 7.0
    mouth = sk.mouth(F, gate_x, 9.0, depth_in=4.0)
    yard = lot.poly.buffer(-0.8, join_style="mitre")
    # The parts bench beside the hall.
    src = None
    for side in (F.pt(hx1 + 2.2, P["hy"] + 3.0), F.pt(hx0 - 2.2, P["hy"] + 3.0)):
        if lot.poly.buffer(-1.5).contains(Point(*side)):
            src = parts_source(ctx, side[0], side[1], F.heading(0, 1), rng)
            break
    park = sk.Parker(site, rng, [hall.buffer(0.5)] + ([src] if src is not None else []),
                     ctx.stats.setdefault("vehicles", {}))
    trucks = 0
    # Trucks nosed to the hall's doors, then more parked round the yard.
    for xd in doors:
        if rng.random() > 0.7:
            continue
        got = pick_truck(park, rng)
        if got is None:
            continue
        name, v, size = got
        x, y = F.pt(hx0 + xd, P["hy"] - 1.2 - size[0] / 2)
        if name in ("dump_truck", "tanker") and int(site.districts.at(x, y)) != INDUSTRIAL:
            continue
        if yard.contains(sk.car_rect(x, y, F.heading(0, 1), size)):
            trucks += park.put("truck", x, y, F.heading(0, 1) + rng.normal(0, 0.05), v, size,
                               source=name not in STRIPPED)
    for _ in range(int(rng.integers(2, 6))):
        got = pick_truck(park, rng)
        if got is None:
            continue
        name, v, size = got
        for _ in range(8):
            p = sk.sample_in(yard.buffer(-size[0] / 2), rng)
            if p is None:
                break
            if name in ("dump_truck", "tanker") and int(site.districts.at(*p)) != INDUSTRIAL:
                continue
            ang = F.ang + rng.choice([0.0, np.pi]) + rng.normal(0, 0.25)
            if park.put("truck", p[0], p[1], ang, v, size, source=name not in STRIPPED):
                trucks += 1
                break
    for _ in range(int(rng.integers(1, 4))):
        p = sk.sample_in(yard.buffer(-3.0), rng)
        if p is not None:
            park.car(p[0], p[1], rng.uniform(0, 2 * np.pi), wreck_share=0.6)
    ctx.count("yard_trucks", trucks)
    for _ in range(int(rng.integers(3, 7))):
        p = sk.sample_in(lot.poly.buffer(-1.0).difference(hall.buffer(1.0)), rng)
        if p is not None:
            sk.clutter(site, str(rng.choice(["tyre_stack", "drums", "pallets", "engine", "tyres"])), p[0], p[1],
                       rng.uniform(0, 6.28))
    ctx.count("truck_yards")
    ctx.place("truck_yard", lot.poly)
    concrete = lot.concrete
    seed = int(rng.integers(1 << 30))
    gate = Point(*F.pt(gate_x, 1.0))
    # The yard's paving stops under the hall's walls (the hall draws its own
    # floor); the oil stains lie in the open yard.
    ground = unary_union([lot.poly, sk.driveway(mouth, lot.poly, concrete)]).difference(
        hall.buffer(-0.2, join_style="mitre"))
    open_yard = lot.poly.difference(hall.buffer(0.3, join_style="mitre"))
    stain_at = lot.poly.buffer(-2.0).difference(hall.buffer(1.0, join_style="mitre"))

    def draw(L):
        r = np.random.default_rng(seed)
        kit.pave(L, ground, 0.23, 0.9, sub="ground", edge=False)
        for _ in range(int(r.integers(4, 9))):
            p = sk.sample_in(stain_at, r)
            if p is not None:
                stain = Point(*p).buffer(r.uniform(1.0, 2.6), quad_segs=3).intersection(open_yard)
                if not stain.is_empty:
                    L.fill("groundlines", stain, 0.05, 0.45)
        kit.fence(L, lot.poly.exterior, r, gate=gate, v=0.3)
    site.drawers.append(draw)


# --------------------------------------------------- car parks and depots

## Standalone car parks: how many, how far apart (m), their lot (m along the
## road, m deep), how full (share of bays) and the roads they open onto,
## with a weight each.
CAR_PARKS = 20
CAR_PARK_SPACING_M = 260.0
CAR_PARK_LOT_M = ((40.0, 70.0), (30.0, 50.0))
CAR_PARK_FULL = (0.4, 0.8)
CAR_PARK_ROADS = {"secondary": 0.6, "tertiary": 0.6, "unclassified": 0.4, "residential": 0.2}

## Bus and minibus depots: how many, how far apart (m), their lot, and their
## bays (m wide, m deep).
BUS_DEPOTS = 5
DEPOT_SPACING_M = 800.0
DEPOT_LOT_M = ((76.0, 96.0), (58.0, 70.0))
BUS_BAY_M = (4.0, 13.5)
MINIBUS_BAY_M = (3.2, 8.2)
## Aisles (m) behind and in front of the depot's middle row of buses. The
## buses (12-13 t) hold a mecha back, so the aisle behind the row and the
## gate lane (DEPOT_GATE_M wide, from the road to that aisle) are wide
## enough for one; the front aisle is narrower, its other side being the
## minibuses (4 t), which a mecha pushes aside.
DEPOT_AISLE_M = (14.0, 8.5)
DEPOT_GATE_M = 14.0


def plan_car_park(ctx, fr, rng):
    length, depth = rng.uniform(*CAR_PARK_LOT_M[0]), rng.uniform(*CAR_PARK_LOT_M[1])
    lot = front_lot(ctx, fr, length, depth, max_cover=0.7)
    if lot is None:
        return None
    F = lot.F
    x0, x1, y0, y1 = sk.box_of(F, lot.poly)
    bays, aisles = sk.bay_grid(F, lot.poly.buffer(-1.8, join_style="mitre"), y_start=y0 + 1.6)
    if len(bays) < 16:
        return None
    # The lot shrinks to its rows and aisles plus a verge, so the ground the
    # rows leave at the back and the ends stays with the houses there.
    used = unary_union([b.poly() for b in bays] + aisles)
    lot = sk.trim_lot(lot, used, verge=2.6)
    x0, x1, _, _ = sk.box_of(F, lot.poly)
    return FrontPlan("car_park", fr, lot, {"drive_x": rng.uniform(x0 + 6.0, x1 - 6.0), "y0": y0})


def build_car_park(ctx, plan):
    site = ctx.site
    lot = settle(ctx, plan, "car_park")
    if lot is None:
        return
    F, P = lot.F, plan.pieces
    rng = sk.place_rng(631, *plan.fr.p)
    bays, aisles = sk.bay_grid(F, lot.poly.buffer(-1.8, join_style="mitre"), y_start=P["y0"] + 1.6)
    dx = P["drive_x"]
    # The driveway reaches the front aisle (the grid starts with it).
    mouth = sk.mouth(F, dx, 7.0, depth_in=P["y0"] + 1.6 + sk.AISLE_M * 0.6)
    bays = [b for b in bays if not b.poly().intersects(mouth)]
    paved = [b.poly() for b in bays] + aisles + [mouth.intersection(lot.poly)]
    apron, islands = sk.shape_ground(lot, paved, [], [sk.driveway(mouth, lot.poly, lot.concrete)],
                                     fillet=2.0, road_verge=2.5)
    park = sk.Parker(site, rng, [g.buffer(-0.3) for g in style.polys(islands)], ctx.stats.setdefault("vehicles", {}))
    cars = park.fill_bays(bays, rng.uniform(*CAR_PARK_FULL), wreck_share=0.08)
    ctx.count("car_parks")
    ctx.place("car_park", lot.poly)
    ctx.count("car_park_bays", len(bays))
    ctx.count("car_park_cars", cars)
    # The attendant's booth on the island nearest the driveway, if one has
    # room for it.
    gate = Point(*F.pt(dx, P["y0"]))
    for g in sorted(style.polys(islands), key=lambda g: g.distance(gate)):
        room = g.buffer(-1.6)
        if room.is_empty or g.distance(gate) > 30.0:
            continue
        p = room.representative_point()
        v, size = hut_variant("guard", (p.x, p.y))
        if v >= 0:
            site.props.add("hut", p.x, p.y, F.ang, size, v)
        break
    concrete = lot.concrete
    arrows = []
    for a in aisles:
        c = a.centroid
        if a.area > 60:
            arrows.append((c.x, c.y, F.u if rng.random() < 0.5 else -F.u))

    def draw(L):
        sk.draw_apron(L, apron, concrete, v=sk.ASPHALT_V, joints=0.0)
        sk.draw_islands(L, islands)
        sk.bay_lines(L, bays)
        for x, y, d in arrows:
            sk.arrow(L, x, y, d, 3.0, sk.MARK_V * 0.9)
    site.drawers.append(draw)


def plan_depot(ctx, fr, rng):
    length, depth = rng.uniform(*DEPOT_LOT_M[0]), rng.uniform(*DEPOT_LOT_M[1])
    lot = front_lot(ctx, fr, length, depth, max_cover=0.75)
    if lot is None:
        return None
    F = lot.F
    x0, x1, y0, y1 = sk.box_of(F, lot.poly)
    hw, hd = rng.uniform(26.0, 34.0), rng.uniform(14.0, 18.0)
    left = rng.random() < 0.5
    hx0 = x0 + 2.0 if left else x1 - 2.0 - hw
    hy = y1 - 2.0 - hd
    hall = F.rect(hx0, hy, hx0 + hw, hy + hd)
    if not lot.fits(hall, 0.8) or hy < 24.0:
        return None
    return FrontPlan("bus_depot", fr, lot, {"hall": hall, "hx": (hx0, hx0 + hw), "hy": hy, "left": left})


def build_depot(ctx, plan):
    site = ctx.site
    lot = settle(ctx, plan, "bus_depot")
    if lot is None:
        return
    F, P = lot.F, plan.pieces
    rng = sk.place_rng(641, *plan.fr.p)
    hall = P["hall"]
    hx0, hx1 = P["hx"]
    doors = [float(x) for x in np.arange(4.5, hx1 - hx0 - 3.0, 7.0)]
    sk.building(site, hall, "workshop_hall", sk.LFrame(F.pt(hx0, P["hy"]), F.u, F.n), doors=doors)
    x0, x1, y0, y1 = sk.box_of(F, lot.poly)
    yard = lot.poly.buffer(-1.0, join_style="mitre")
    side = F.pt(hx1 + 2.0 if P["left"] else hx0 - 2.0, P["hy"] + 2.5)
    src = parts_source(ctx, side[0], side[1], F.heading(0, 1), rng) \
        if lot.poly.buffer(-1.5).contains(Point(*side)) else None
    park = sk.Parker(site, rng, [hall.buffer(0.6)] + ([src] if src is not None else []),
                     ctx.stats.setdefault("vehicles", {}))
    # The bus row beside the hall, noses to the back of the lot, under a
    # canopy; the minibus row along the front, noses to the road.
    bx0, bx1 = (hx1 + 3.0, x1 - 2.0) if P["left"] else (x0 + 2.0, hx0 - 3.0)
    yb = y1 - 2.0 - BUS_BAY_M[1]
    bus_bays = sk.bay_row(F, bx0, bx1, yb, +1, yard, w=BUS_BAY_M[0], depth=BUS_BAY_M[1])
    mini_bays = sk.bay_row(F, x0 + 6.0, x1 - 6.0, y0 + 2.5 + MINIBUS_BAY_M[1], -1, yard, w=MINIBUS_BAY_M[0],
                           depth=MINIBUS_BAY_M[1])
    gate_x = (x0 + x1) / 2
    mouth = sk.mouth(F, gate_x, DEPOT_GATE_M, depth_in=MINIBUS_BAY_M[1] + 4.0)
    mini_bays = [b for b in mini_bays if not b.poly().intersects(mouth)]
    # A row parked in the open between them, noses to the front, with
    # DEPOT_AISLE_M behind it and in front of it, clear of the hall and the
    # gate lane (which stays open from the road to the back): buses where
    # the lot is deep enough, else minibuses.
    ym = yb - DEPOT_AISLE_M[0]
    bus_bays_open, mid = [], None
    for kind, (bw, bd) in (("bus", BUS_BAY_M), ("minibus", MINIBUS_BAY_M)):
        if ym - bd >= y0 + 2.5 + MINIBUS_BAY_M[1] + DEPOT_AISLE_M[1]:
            keep_off = unary_union([hall.buffer(5.0), F.rect(gate_x - DEPOT_GATE_M / 2, y0 - 5.0,
                                                             gate_x + DEPOT_GATE_M / 2, y1 + 5.0)])
            bus_bays_open = [b for b in sk.bay_row(F, x0 + 2.0, x1 - 2.0, ym, -1, yard, w=bw, depth=bd)
                             if not b.poly().intersects(keep_off)]
            mid = kind
            break
    buses = minis = 0
    for b in bus_bays:
        got = park.pick("bus") if rng.random() < 0.8 else None
        if got is not None:
            ang = float(np.arctan2(b.d[1], b.d[0])) + rng.normal(0, 0.03)
            buses += park.put("bus", b.x, b.y, ang, got[0], got[1])
    for b in bus_bays_open:
        if rng.random() >= 0.65:
            continue
        got = park.pick("bus") if mid == "bus" else park.pick("truck", names=("minibus",))
        if got is not None:
            ang = float(np.arctan2(b.d[1], b.d[0])) + rng.normal(0, 0.04) + (np.pi if rng.random() < 0.2 else 0.0)
            if mid == "bus":
                buses += park.put("bus", b.x, b.y, ang, got[0], got[1])
            else:
                minis += park.put("truck", b.x, b.y, ang, got[0], got[1])
    for b in mini_bays:
        got = park.pick("truck", names=("minibus",)) if rng.random() < 0.7 else None
        if got is not None:
            ang = float(np.arctan2(b.d[1], b.d[0])) + rng.normal(0, 0.03) + (np.pi if rng.random() < 0.3 else 0.0)
            minis += park.put("truck", b.x, b.y, ang, got[0], got[1])
    # A few left standing askew in the yard, off the gate lane and the
    # aisle behind the middle row.
    lanes = F.rect(gate_x - DEPOT_GATE_M / 2, y0 - 5.0, gate_x + DEPOT_GATE_M / 2, yb)
    if bus_bays_open:
        lanes = lanes.union(F.rect(x0 - 5.0, ym, x1 + 5.0, yb))
    for _ in range(int(rng.integers(1, 4))):
        p = sk.sample_in(yard.buffer(-6.0), rng)
        got = park.pick("bus") if p is not None else None
        if got is not None:
            ang = F.ang + rng.choice([0.0, np.pi / 2, np.pi, -np.pi / 2]) + rng.normal(0, 0.25)
            if not lanes.intersects(sk.car_rect(p[0], p[1], ang, got[1])):
                buses += park.put("bus", p[0], p[1], ang, got[0], got[1])
    ctx.count("bus_depots")
    ctx.place("bus_depot", lot.poly)
    ctx.count("depot_buses", buses)
    ctx.count("depot_minibuses", minis)
    shelter = None
    if bus_bays:
        xs = [F.to_local(b.x, b.y)[0] for b in bus_bays]
        shelter = F.rect(min(xs) - BUS_BAY_M[0] / 2, yb + 1.5, max(xs) + BUS_BAY_M[0] / 2, yb + BUS_BAY_M[1] + 0.8)
    concrete = lot.concrete
    seed = int(rng.integers(1 << 30))
    gate = Point(*F.pt(gate_x, 1.0))
    ground = unary_union([lot.poly, sk.driveway(mouth, lot.poly, concrete)]).difference(
        hall.buffer(-0.2, join_style="mitre"))

    def draw(L):
        r = np.random.default_rng(seed)
        kit.pave(L, ground, sk.ASPHALT_V, 0.95, sub="ground", edge=False)
        sk.bay_lines(L, bus_bays + mini_bays + bus_bays_open)
        kit.wall(L, lot.poly.exterior, 0.35, 0.3, gate=gate)
        if shelter is not None:
            sk.canopy(L, shelter, F, r, v=0.17)
            sx0, sx1, sy0, sy1 = sk.box_of(F, shelter)
            for x in np.arange(sx0 + 0.5, sx1, 8.0):
                for y in (sy0 + 0.4, sy1 - 0.4):
                    L.fill("interiors", F.rect(x - 0.2, y - 0.2, x + 0.2, y + 0.2), 0.1)
    site.drawers.append(draw)


# ----------------------------------------------------------------- garages

## Backstreet garages: how many, how far apart (m), the share that clear the
## next house into a yard, and the street kinds they open onto.
GARAGES = 30
GARAGE_SPACING_M = 140.0
GARAGE_YARD_SHARE = 0.5
GARAGE_STREETS = {"residential", "unclassified", "tertiary", "service", "tertiary_link"}
## The open bay's width (m, drawn from this range, at most the street side
## less 1.2 m).
GARAGE_BAY_W_M = (5.0, 7.0)


class GaragePlan:
    def __init__(self, house, edge, yard_house):
        self.house, self.edge, self.yard_house = house, edge, yard_house
        self.lot = sk.Lot(unary_union([house] + ([yard_house] if yard_house is not None else [])).buffer(0.3),
                          None, None, "garage")


def street_edge(ctx, poly, kinds):
    """The longest straight side of a house that faces a street of the
    given kinds (its middle within 2.6 m of the concrete): (a, b, the
    outward unit normal) or None."""
    pts = np.asarray(poly.exterior.coords)
    best = None
    for a, b in zip(pts[:-1], pts[1:]):
        L = float(np.hypot(*(b - a)))
        if L < 6.0:
            continue
        d = (b - a) / L
        n = np.array([-d[1], d[0]])
        m = (a + b) / 2
        if poly.contains(Point(*(m + n * 0.5))):
            n = -n
        r = ctx.R.at(*(m + n * 1.6), tol=1.5)
        if r is None or r[2] not in kinds or ctx.R.rail_near(*(m + n * 2.0)):
            continue
        if best is None or L > best[0]:
            best = (L, a, b, n)
    return None if best is None else best[1:]


def choose_garages(ctx):
    houses = ctx.lots
    cands = []
    for i, h in enumerate(houses):
        c = h.centroid
        if sk.place_hash(401, c.x, c.y) > 0.03 or not (60.0 <= h.area <= 220.0):
            continue
        if not ctx.inner.contains(c) or int(ctx.D.at(c.x, c.y)) not in (RESIDENTIAL, MARKET):
            continue
        cands.append(i)
    cands.sort(key=lambda i: sk.place_hash(403, *houses[i].centroid.coords[0]))
    block_tree = STRtree(ctx.blocks)
    chosen, pts = [], []
    for i in cands:
        if len(chosen) >= GARAGES:
            break
        h = houses[i]
        c = np.array(h.centroid.coords[0])
        if pts and np.min(np.hypot(*(np.asarray(pts) - c).T)) < GARAGE_SPACING_M:
            continue
        blk = [ctx.blocks[j] for j in block_tree.query(Point(*c)) if ctx.blocks[j].contains(Point(*c))]
        if not blk or ctx.block_use(blk[0]) is not None:
            continue
        edge = street_edge(ctx, h, GARAGE_STREETS)
        if edge is None or ctx.mine_hits(h, 3.0) or ctx.big_share(h.buffer(3.0)) > 0.0 or ctx.blocked(h.buffer(8.0)):
            continue
        yard = None
        rng = sk.place_rng(405, *c)
        if rng.random() < GARAGE_YARD_SHARE:
            near = [houses[j] for j in ctx.lot_tree.query(h.buffer(2.5)) if j != i]
            for g in sorted(near, key=lambda g: g.distance(h)):
                if g.area > 260 or g.distance(h) > 2.0:
                    continue
                e2 = street_edge(ctx, g, GARAGE_STREETS)
                if e2 is not None and abs(float(e2[2] @ edge[2])) > 0.9:
                    yard = g
                    break
        plan = GaragePlan(h, edge, yard)
        chosen.append(plan)
        pts.append(c)
        ctx.reserve(plan.lot.poly)
    ctx.stats["garages_chosen"] = len(chosen)
    return chosen


def find_house(site, poly):
    """The generated house (stage "lots") with this footprint, if it is still
    on the map."""
    c = poly.centroid
    for b in sk.buildings_near(site, poly, 0.0):
        if b.kind == "house" and b.opts.get("stage") == "lots":
            bc = b.poly.centroid
            if abs(bc.x - c.x) < 0.05 and abs(bc.y - c.y) < 0.05:
                return b
    return None


def build_garage(ctx, plan):
    site = ctx.site
    b = find_house(site, plan.house)
    if b is None or not site.is_free(plan.house.buffer(-0.3), districts=False):
        ctx.count("garages_skipped")
        return
    a, e, n = plan.edge
    a, e = np.asarray(a), np.asarray(e)
    width = float(np.hypot(*(e - a)))
    u = (e - a) / width
    F = sk.LFrame(a, u, -n)
    hc = plan.house.centroid
    rng = sk.place_rng(407, hc.x, hc.y)
    bay_w = min(rng.uniform(*GARAGE_BAY_W_M), width - 1.2)
    bay_x = rng.uniform(bay_w / 2 + 0.5, width - bay_w / 2 - 0.5)
    b.kind = "garage"
    b.opts.update(front_o=tuple(F.o), front_u=tuple(F.u), front_n=tuple(F.n), bay_x=bay_x, bay_w=bay_w)
    sk.pin_state(site, b)
    site.claim(plan.house, "sites:garage")
    ctx.count("garages")
    ctx.place("garage", plan.house)
    yard = None
    if plan.yard_house is not None:
        yb = find_house(site, plan.yard_house)
        if yb is not None and site.is_free(plan.yard_house.buffer(-0.3), districts=False):
            site.buildings = [bb for bb in site.buildings if bb is not yb]
            yard = sk.largest(plan.yard_house.buffer(0.3, join_style="mitre").difference(b.poly.buffer(0.2)))
    concrete = site.road_union_near(plan.house, 12.0)
    if concrete is None or concrete.is_empty:
        return
    right = bay_x + bay_w / 2 + 2.5 < width
    px, py = F.pt(bay_x + bay_w / 2 + 1.5 if right else bay_x - bay_w / 2 - 1.5, -0.75)
    src = parts_source(ctx, px, py, F.ang, rng, 2.2, 1.0)
    near = [bb.poly.buffer(0.3) for bb in sk.buildings_near(site, plan.house, 25.0)]
    park = sk.Parker(site, rng, near + ([src] if src is not None else []), ctx.stats.setdefault("vehicles", {}))
    # The street side: the kerb (the concrete's edge) runs `kerb` m in
    # front of the wall; cars may stand on the concrete and the strip
    # between it and the wall.
    kerb = float(concrete.distance(Point(*F.pt(width / 2, 0.0))))
    street = concrete.union(F.rect(-3.0, -kerb - 0.2, width + 3.0, -0.2)).buffer(-0.1)
    # Out front: a car or wreck nosed into the bay (shorter ones are tried
    # where the lane is narrow), then tyres and drums along the wall on both
    # sides of the mouth, the side without the parts pile first, then one or
    # two cars along the kerb beside the bay (the first in front of the bay
    # when no car could nose into it).
    kerb_xs = []
    for max_len in (5.4, 4.6, 4.1):
        got = park.pick("vehicle", max_len)
        if got is None:
            continue
        v, size = got
        p = F.pt(bay_x + rng.uniform(-0.4, 0.4), -0.5 - size[0] / 2)
        ang = F.heading(0, 1) + rng.normal(0, 0.1)
        kind = "vehicle_wreck" if rng.random() < 0.35 else "vehicle"
        if park.put(kind, p[0], p[1], ang, v, size, on_road=True, concrete=street):
            ctx.count("garage_bay_cars")
            break
    else:
        kerb_xs.append(bay_x)
    sides = (-1, 1) if right else (1, -1)
    slots = [(s, off) for off in (0.9, 2.0, 3.1) for s in sides]
    k = 0
    for name in ("tyre_stack", "drums", "tyres"):
        while k < len(slots):
            s, off = slots[k]
            k += 1
            x = bay_x + s * (bay_w / 2 + off)
            if not -1.5 <= x <= width + 1.5:
                continue
            q = F.pt(x, -0.8 + rng.uniform(-0.15, 0.15))
            if sk.clutter(site, name, q[0], q[1], F.ang + rng.normal(0, 0.2), clear=0.0):
                break
    kerb_xs += [bay_x + s * rng.uniform(4.6, 6.0) for s in sides]
    for x in kerb_xs[:int(rng.integers(1, 3))]:
        got = park.pick("vehicle", 5.4)
        if got is None:
            break
        v, size = got
        p = F.pt(x, -kerb - 0.3 - size[1] / 2)
        ang = F.ang + (np.pi if rng.random() < 0.5 else 0.0) + rng.normal(0, 0.08)
        kind = "vehicle_wreck" if rng.random() < 0.35 else "vehicle"
        park.put(kind, p[0], p[1], ang, v, size, on_road=True, concrete=street)
    if yard is not None:
        site.claim(yard, "sites:garage_yard")
        site.clear_area(yard)
        site.solid_extra.append(yard)
        ctx.count("garage_yards")
        inner = yard.buffer(-0.5)
        for _ in range(int(rng.integers(1, 4))):
            p = sk.sample_in(inner.buffer(-1.6), rng)
            if p is not None:
                park.car(p[0], p[1], F.ang + rng.choice([0.0, np.pi / 2, np.pi]) + rng.normal(0, 0.3), wreck_share=0.55)
        for _ in range(int(rng.integers(2, 5))):
            p = sk.sample_in(inner.buffer(-0.8), rng)
            if p is not None:
                sk.clutter(site, str(rng.choice(["tyre_stack", "engine", "drums", "tyres", "crates"])), p[0], p[1],
                           rng.uniform(0, 6.28), clear=0.0)
    seed = int(rng.integers(1 << 30))
    # The oil stain spreads over the strip between the bay and the kerb, not
    # onto the street's concrete or into the buildings.
    stain = F.pt(bay_x, -min(1.6, kerb / 2))
    stain_off = unary_union([concrete] + near)
    street_side = F.rect(-1.0, -6.0, width + 1.0, 1.5) if yard is None else \
        sk.LFrame(a, u, -n).rect(-40.0, -6.0, 40.0, 1.2)

    def draw(L):
        r = np.random.default_rng(seed)
        g = Point(*stain).buffer(r.uniform(1.6, 2.4), quad_segs=3).difference(stain_off)
        if not g.is_empty:
            L.fill("groundlines", g, 0.03, 0.45)
        if yard is not None:
            L.fill("ground", yard, 0.13, 0.9)
            for _ in range(3):
                p = sk.sample_in(yard.buffer(-1.0), r)
                if p is not None:
                    L.fill("groundlines", Point(*p).buffer(r.uniform(0.6, 1.5), quad_segs=3).intersection(yard),
                           0.03, 0.45)
            edge = LineString(yard.exterior.coords).difference(street_side)
            for part in getattr(edge, "geoms", [edge]):
                if part.length > 1.0:
                    L.line("interiors", part, 0.6, 0.02, 0.5)
                    L.line("interiors", part, 0.3, 0.28)
    site.drawers.append(draw)


# -------------------------------------------------------- parking out front

## Where the front of a large roof, or of a generated building of at least
## FRONT_LOT_MIN_M2, is at least FRONT_MIN_M from the road (and at most
## FRONT_MAX_M) and the strip is free of houses, FRONT_SHARE of such strips
## become bays: straight in when there is BAY_D of room, angled when there
## is less, two rows and an aisle when there is room for them; FRONT_FULL
## full. A strip is built only while its building still stands.
FRONT_MIN_M = 6.0
FRONT_MAX_M = 26.0
FRONT_SHARE = 0.9
FRONT_FULL = (0.4, 0.8)
FRONT_LOT_MIN_M2 = 300.0
GAP_PROBES = np.arange(1.0, FRONT_MAX_M + 1.0, 0.5)


def front_strips(ctx):
    """Strips between large buildings and the road in front of them: (strip
    polygon, frame with x along the front and y from the road towards the
    building, depth for bays in m, length in m, the building's outline)."""
    out = []
    block_tree = STRtree(ctx.blocks)
    fronts = [g for g in ctx.big if g.area >= 250] + [g for g in ctx.lots if g.area >= FRONT_LOT_MIN_M2]
    for g in fronts:
        if not ctx.inner.contains(g.centroid):
            continue
        c = g.representative_point()
        blk = [ctx.blocks[j] for j in block_tree.query(c) if ctx.blocks[j].contains(c)]
        if not blk or ctx.block_use(blk[0]) is not None:
            continue
        pts = np.asarray(g.exterior.coords)
        for a, b in zip(pts[:-1], pts[1:]):
            L = float(np.hypot(*(b - a)))
            if L < 12.0:
                continue
            d = (b - a) / L
            n = np.array([-d[1], d[0]])
            m = (a + b) / 2
            if g.contains(Point(*(m + n * 0.5))):
                n = -n
            if sk.place_hash(501, *m) > FRONT_SHARE:
                continue
            # How far the road's concrete is from the wall, at three points
            # along it (the first of the probes every 0.5 m that is inside
            # the concrete).
            probes = np.concatenate([a + (b - a) * t + np.outer(GAP_PROBES, n) for t in (0.2, 0.5, 0.8)])
            hit = ctx.R.ctree.query(shapely.points(probes), predicate="within")[0]
            first = [hit[(hit >= k * len(GAP_PROBES)) & (hit < (k + 1) * len(GAP_PROBES))] for k in range(3)]
            if any(len(h) == 0 for h in first):
                continue
            gap = min(float(GAP_PROBES[int(h.min()) % len(GAP_PROBES)]) for h in first)
            if gap < FRONT_MIN_M:
                continue
            if ctx.R.at(*(m + n * (gap + 1.0)), tol=2.0) is None or ctx.R.rail_near(*(m + n * gap)):
                continue
            F = sk.LFrame(a + n * gap, d, -n)
            strip = F.rect(0.8, 0.6, L - 0.8, gap - 0.5)
            if ctx.house_cover(strip) > 0.02 or ctx.big_share(strip) > 0.0 or ctx.mine_hits(strip, 1.0) or \
                    ctx.blocked(strip):
                continue
            # The gap is measured at three points: where the road bends or a
            # side street meets it between them, the strip is cut off its
            # concrete (the bays are only where they fit wholly in the strip).
            conc = ctx.R.concrete_near(strip, 2.0)
            if conc.intersects(strip):
                strip = sk.largest(strip.difference(conc))
                if strip is None or strip.area < 2 * sk.BAY_W * sk.BAY_D:
                    continue
            out.append((strip, F, gap - 1.1, L - 1.6, g))
            ctx.reserve(strip)
    ctx.stats["front_strips_chosen"] = len(out)
    return out


def standing(site, poly):
    """True while a building with (nearly) this outline is on the map."""
    c = poly.centroid
    for b in sk.buildings_near(site, poly, 0.0):
        if b.poly.intersection(poly).area > 0.8 * poly.area and b.poly.centroid.distance(c) < 1.0:
            return True
    return False


def build_front(ctx, strip, F, depth, length, front):
    site = ctx.site
    if not standing(site, front):
        ctx.count("front_strips_skipped")
        return
    # The strip less the land other modules took and the houses on it (a
    # strip may touch the corner of one).
    free = sk.free_part(site, strip)
    near = [b.poly.buffer(0.5, join_style="mitre") for b in sk.buildings_near(site, strip, 0.5)]
    if free is not None and near:
        free = sk.largest(free.difference(unary_union(near)))
    if free is None or free.area < 0.95 * strip.area:
        ctx.count("front_strips_skipped")
        return
    c = strip.centroid
    rng = sk.place_rng(503, c.x, c.y)
    strip = free.simplify(0.05)
    area = strip.buffer(0.05)
    if depth >= 2 * sk.BAY_D + sk.AISLE_M + 0.5:
        bays = sk.bay_row(F, 0.8, length + 0.8, 0.6 + sk.BAY_D, -1, area)
        bays += sk.bay_row(F, 0.8, length + 0.8, 0.6 + sk.BAY_D + sk.AISLE_M, +1, area)
    elif depth >= sk.BAY_D:
        bays = sk.bay_row(F, 0.8, length + 0.8, 0.6, +1, area)
    else:
        bays = sk.bay_row(F, 0.8, length + 0.8, 0.6, +1, area, depth=min(depth, 5.0), angle=55.0)
    if not bays:
        return
    site.claim(strip, "sites:front_parking")
    site.clear_area(strip)
    site.solid_extra.append(strip)
    park = sk.Parker(site, rng, [b.poly.buffer(0.3) for b in sk.buildings_near(site, strip, 1.0)],
                     ctx.stats.setdefault("vehicles", {}))
    cars = park.fill_bays(bays, rng.uniform(*FRONT_FULL), wreck_share=0.07, reverse_share=0.15)
    ctx.count("front_strips")
    ctx.place("front_parking", strip)
    ctx.count("front_bays", len(bays))
    ctx.count("front_cars", cars)
    kerb = F.line([(0.8, depth + 0.5), (length + 0.8, depth + 0.5)]).intersection(strip.buffer(0.3))

    def draw(L):
        L.fill("ground", strip, sk.ASPHALT_V, 0.95)
        L.line("groundlines", kerb, sk.KERB_W, sk.KERB_V, 0.9)
        sk.bay_lines(L, bays)
    site.drawers.append(draw)


# ------------------------------------------------------- side car parks

## Large buildings (over SIDE_MIN_M2) with open ground beside them that
## reaches a road get a side car park on that ground: SIDE_SHARE of them, at
## most SIDE_PARKS over the map. The car park is an aisle along the wall and
## one or two rows of bays beyond it (SIDE_DEPTH_M), open to the road at its
## end; houses there are cleared when they cover at most SIDE_MAX_COVER of
## it.
SIDE_PARKS = 40
SIDE_SHARE = 0.6
SIDE_MIN_M2 = 600.0
SIDE_LOT_MIN_M2 = 400.0
SIDE_DEPTH_M = (sk.AISLE_M + sk.BAY_D + 1.6, sk.AISLE_M + 2 * sk.BAY_D + 1.8)
SIDE_MAX_COVER = 0.3


def side_parks(ctx):
    """Side car parks beside large roofs (over SIDE_MIN_M2) and generated
    buildings (over SIDE_LOT_MIN_M2): (lot polygon, frame with x along the
    wall and y away from it, the road end's local x, the road concrete
    there, the building's outline)."""
    out = []
    block_tree = STRtree(ctx.blocks)
    walls = [g for g in ctx.big if g.area >= SIDE_MIN_M2] + [g for g in ctx.lots if g.area >= SIDE_LOT_MIN_M2]
    for g in sorted(walls, key=lambda g: -g.area):
        if len(out) >= SIDE_PARKS:
            break
        if not ctx.inner.contains(g.centroid):
            continue
        c = g.representative_point()
        if sk.place_hash(511, c.x, c.y) > SIDE_SHARE:
            continue
        blk = [ctx.blocks[j] for j in block_tree.query(c) if ctx.blocks[j].contains(c)]
        if not blk or ctx.block_use(blk[0]) is not None:
            continue
        blk = blk[0]
        pts = np.asarray(g.exterior.coords)
        best = None
        for a, b in zip(pts[:-1], pts[1:]):
            L = float(np.hypot(*(b - a)))
            if L < 18.0:
                continue
            d = (b - a) / L
            n = np.array([-d[1], d[0]])
            if g.contains(Point(*((a + b) / 2 + n * 0.5))):
                n = -n
            for depth in SIDE_DEPTH_M[::-1]:
                F = sk.LFrame(a, d, n)
                rect = F.rect(0.0, 1.0, L, 1.0 + depth)
                lot = sk.largest(blk.intersection(rect))
                if lot is None or lot.area < 0.9 * rect.area:
                    continue
                conc = ctx.R.concrete_near(rect, 4.0)
                if conc.is_empty or not rect.buffer(2.0).intersects(conc):
                    continue
                lot = sk.largest(lot.difference(conc.buffer(sk.ROAD_SETBACK_M)))
                if lot is None or lot.area < 0.82 * rect.area or ctx.big_share(lot) > 0.0:
                    continue
                if ctx.house_cover(lot) > SIDE_MAX_COVER or ctx.mine_hits(lot, 2.0) or ctx.blocked(lot):
                    continue
                ends = [x for x in (0.0, L) if Point(*F.pt(x, 1.0 + depth / 2)).distance(conc) < 4.0]
                if not ends:
                    continue
                if best is None or lot.area > best[0].area:
                    best = (lot, F, ends[0], conc, g)
                break
        if best is not None:
            out.append(best)
            ctx.reserve(best[0])
    ctx.stats["side_parks_chosen"] = len(out)
    return out


def build_side_park(ctx, poly, F, end_x, concrete, wall):
    site = ctx.site
    free = sk.free_part(site, poly)
    if free is None or free.area < 0.95 * poly.area or not standing(site, wall):
        ctx.count("side_parks_skipped")
        return
    c = poly.centroid
    rng = sk.place_rng(513, c.x, c.y)
    lot, dropped = sk.take_land(site, sk.Lot(free, F, concrete, "side"), "sites:side_park")
    ctx.count("houses_removed", dropped)
    x0, x1, y0, y1 = sk.box_of(F, lot.poly)
    area = lot.poly.buffer(-0.6, join_style="mitre")
    bays, aisles = sk.bay_grid(F, area)
    mouth = sk.driveway(F.rect(end_x - 6.0, y0, end_x + 6.0, y1).intersection(concrete.buffer(1.6)).union(
        F.rect(end_x - 6.0 if end_x > x0 + 1 else end_x, y0 + 0.4, end_x if end_x > x0 + 1 else end_x + 6.0,
               y0 + 0.4 + sk.AISLE_M)), lot.poly, concrete)
    bays = [b for b in bays if not b.poly().intersects(mouth.buffer(0.3))]
    # The bays, aisles and the way in are paved; the ground they leave (the
    # plots of the houses the lot grew over, its corners) becomes kerbed
    # islands.
    paved = [b.poly() for b in bays] + aisles + [mouth.intersection(lot.poly)]
    apron, islands = sk.shape_ground(lot, paved, [], [mouth], fillet=2.0, road_verge=2.5)
    park = sk.Parker(site, rng, [b.poly.buffer(0.3) for b in sk.buildings_near(site, lot.poly, 1.0)] +
                     [g.buffer(-0.3) for g in style.polys(islands)], ctx.stats.setdefault("vehicles", {}))
    cars = park.fill_bays(bays, rng.uniform(0.35, 0.75), wreck_share=0.08)
    ctx.count("side_parks")
    ctx.place("side_park", lot.poly)
    ctx.count("side_park_bays", len(bays))
    ctx.count("side_park_cars", cars)
    edge = LineString(lot.poly.exterior.coords).difference(concrete.buffer(2.0))

    def draw(L):
        sk.draw_apron(L, apron, concrete, v=sk.ASPHALT_V, joints=0.0)
        sk.draw_islands(L, islands)
        L.line("groundlines", edge, sk.KERB_W, sk.KERB_V, 0.9)
        sk.bay_lines(L, bays)
    site.drawers.append(draw)
