"""Draws simple top-down placeholder sprites for the new prop kinds, until
Yosqi draws the real art. Writes them into inputs/sprites/, where
prep_sprites.py picks them up like the hand-drawn ones.

Usage: python make_placeholders.py

  vehicle_bus_city, vehicle_bus_coach          kind "bus"
  vehicle_tank_west, vehicle_tank_east,
  vehicle_apc, vehicle_military_truck          kind "military"
  vehicle_container_truck, vehicle_tanker,
  vehicle_dump_truck                           kind "truck"
  vehicle_container_20ft_a/_b, _40ft           kind "container"
  vehicle_metro_cab, _metro_car, _boxcar,
  _flatcar, _flatcar_container, _hopper        kind "railcar"
  stall_<name>.png and stall_<name>_broken.png kind "stall": lean_to, canopy,
                                               table, hand_cart
  hut_<name>.png and hut_<name>_broken.png     kind "hut": guard, cabin, shed,
                                               shelter, kiosk, tent
  clutter_<name>.png                           kind "clutter": drums, pallets,
                                               reel, cylinders, cabinet,
                                               hydrant, sleepers, skid,
                                               rubbish, tyres, crates, sacks,
                                               tarp, washing, genset,
                                               haystack, cart, jerrycans,
                                               sandbags, fuel_pump, air_post,
                                               tyre_stack, engine

Vehicles are drawn front up, like the other vehicle sources (prep_sprites
turns them to face +x). Stalls are drawn as the game uses them: the counter
along x, the front (where buyers stand) facing +y. A broken stall has the
same canvas and scale as its intact one, with its pieces thrown towards +x
(the game turns it to the push direction) and its goods spilled round it.
Huts are drawn with the long side along x. A broken hut (a ruin) is on its
intact hut's canvas and scale.

Greys follow the hand-drawn cars: dark bodies (about 20-60) with lighter
edge lines, so the shaders' tones apply the same way.
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "inputs", "sprites")
V_PX = 20  # px per metre for vehicles, as the hand-drawn cars
S_PX = 32  # px per metre for stalls


def grey(v, a=255):
    return (v, v, v, a)


class Pen:
    """Draws in metres on a canvas, origin at the canvas centre, y down."""

    def __init__(self, w_m, h_m, ppm, pad_m=0.4):
        self.ppm = ppm
        self.w = int(round((w_m + 2 * pad_m) * ppm))
        self.h = int(round((h_m + 2 * pad_m) * ppm))
        self.im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def p(self, x, y):
        return (self.w / 2 + x * self.ppm, self.h / 2 + y * self.ppm)

    def rect(self, x0, y0, x1, y1, fill, outline=None, width=1, r=0.0):
        box = [self.p(x0, y0), self.p(x1, y1)]
        if r > 0:
            self.d.rounded_rectangle(box, radius=r * self.ppm, fill=fill, outline=outline, width=width)
        else:
            self.d.rectangle(box, fill=fill, outline=outline, width=width)

    def poly(self, pts, fill, outline=None, width=1):
        self.d.polygon([self.p(x, y) for x, y in pts], fill=fill, outline=outline, width=width)

    def line(self, pts, fill, width_m):
        self.d.line([self.p(x, y) for x, y in pts], fill=fill, width=max(1, int(round(width_m * self.ppm))))

    def disc(self, x, y, r, fill, outline=None, width=1):
        self.d.ellipse([self.p(x - r, y - r), self.p(x + r, y + r)], fill=fill, outline=outline, width=width)

    def grain(self, rng, amount=6):
        a = np.asarray(self.im).astype(np.int16)
        noise = rng.integers(-amount, amount + 1, a.shape[:2])
        a[..., :3] = np.clip(a[..., :3] + noise[..., None], 0, 255)
        self.im = Image.fromarray(a.astype(np.uint8))
        self.d = ImageDraw.Draw(self.im)

    def save(self, name):
        self.im.save(os.path.join(OUT, name))


def bus(name, length, coach, rng):
    w = 2.55
    P = Pen(w, length, V_PX)
    hl, hw = length / 2, w / 2
    P.rect(-hw, -hl, hw, hl, grey(30), grey(78), 2, r=0.35)
    P.rect(-hw + 0.15, -hl + 0.12, hw - 0.15, -hl + 1.1, grey(12), r=0.2)
    P.rect(-hw + 0.15, hl - 0.55, hw - 0.15, hl - 0.12, grey(16), r=0.15)
    for y in np.arange(-hl + 1.4, hl - 0.8, 0.95):
        P.line([(-hw + 0.08, y), (-hw + 0.08, y + 0.7)], grey(14), 0.12)
        P.line([(hw - 0.08, y), (hw - 0.08, y + 0.7)], grey(14), 0.12)
    if coach:
        P.rect(-hw + 0.4, -hl + 1.5, hw - 0.4, hl - 1.2, grey(36), grey(50), 1, r=0.3)
        P.rect(-0.7, -hl + 2.2, 0.7, -hl + 3.6, grey(44), grey(70), 1)
    else:
        P.rect(-0.8, -hl + 1.6, 0.8, -hl + 3.4, grey(46), grey(72), 1)
        for y in (-hl + 5.0, 0.8, hl - 3.0):
            P.rect(-0.55, y, 0.55, y + 0.9, grey(22), grey(60), 1)
        P.line([(0, -hl + 3.6), (0, hl - 1.0)], grey(40), 0.08)
    P.grain(rng)
    P.save(f"vehicle_{name}.png")


def tracks(P, y0, y1, hw, tw):
    for side in (-1, 1):
        x0 = -hw if side < 0 else hw - tw
        P.rect(x0, y0, x0 + tw, y1, grey(18), grey(52), 1)
        for y in np.arange(y0 + 0.1, y1, 0.32):
            P.line([(x0 + 0.05, y), (x0 + tw - 0.05, y)], grey(34), 0.06)


def tank(name, hull_l, hull_w, overhang, turret_round, rng):
    """overhang: how far the gun reaches past the hull's front."""
    total = hull_l + overhang
    P = Pen(hull_w, total, V_PX)
    front, back = -total / 2 + overhang, total / 2
    hw, tw = hull_w / 2, 0.62
    tracks(P, front, back, hw, tw)
    P.rect(-hw + tw, front, hw - tw, back, grey(34), grey(66), 1)
    P.poly([(-hw + tw, front), (hw - tw, front), (hw - tw - 0.1, front + 0.5), (-hw + tw + 0.1, front + 0.5)], grey(26))
    P.rect(-hw + 0.9, back - 1.6, hw - 0.9, back - 0.25, grey(24), grey(48), 1)
    for x in np.linspace(-hw + 1.1, hw - 1.1, 5):
        P.line([(x, back - 1.5), (x, back - 0.35)], grey(40), 0.06)
    ty = (front + back) / 2 + 0.3
    P.line([(0, ty), (0, -total / 2)], grey(22), 0.24)
    P.line([(0, -total / 2), (0, -total / 2 + 0.6)], grey(14), 0.3)
    if turret_round:
        P.disc(0, ty, 1.4, grey(40), grey(76), 2)
        P.disc(0.55, ty + 0.35, 0.36, grey(28), grey(62), 1)
    else:
        P.poly([(-1.7, ty - 1.2), (1.7, ty - 1.2), (1.9, ty + 0.6), (1.4, ty + 1.9), (-1.4, ty + 1.9), (-1.9, ty + 0.6)],
               grey(40), grey(76), 2)
        P.rect(0.4, ty + 0.1, 1.2, ty + 0.9, grey(28), grey(62), 1)
        P.rect(-1.25, ty + 0.2, -0.55, ty + 0.9, grey(28), grey(62), 1)
    P.grain(rng)
    P.save(f"vehicle_{name}.png")


def apc(rng):
    length, w = 7.6, 2.9
    P = Pen(w, length, V_PX)
    hl, hw = length / 2, w / 2
    for y in (-2.3, -0.9, 0.9, 2.3):
        for side in (-1, 1):
            x0 = -hw if side < 0 else hw - 0.38
            P.rect(x0, y - 0.55, x0 + 0.38, y + 0.55, grey(14), grey(40), 1)
    P.poly([(-hw + 0.3, -hl + 1.2), (-0.6, -hl), (0.6, -hl), (hw - 0.3, -hl + 1.2), (hw - 0.3, hl - 0.2),
            (-hw + 0.3, hl - 0.2)], grey(34), grey(70), 2)
    P.poly([(-hw + 0.5, -hl + 1.4), (-0.5, -hl + 0.35), (0.5, -hl + 0.35), (hw - 0.5, -hl + 1.4)], grey(24))
    P.disc(0, -0.8, 0.8, grey(42), grey(74), 2)
    P.line([(0, -0.8), (0, -hl - 0.1)], grey(20), 0.12)
    for y in (0.8, 2.0):
        P.rect(-0.9, y, -0.2, y + 0.8, grey(26), grey(56), 1)
        P.rect(0.2, y, 0.9, y + 0.8, grey(26), grey(56), 1)
    P.grain(rng)
    P.save("vehicle_apc.png")


def military_truck(rng):
    length, w = 8.0, 2.5
    P = Pen(w, length, V_PX)
    hl, hw = length / 2, w / 2
    P.rect(-hw + 0.1, -hl, hw - 0.1, -hl + 2.3, grey(32), grey(70), 2, r=0.2)
    P.rect(-hw + 0.25, -hl + 0.15, hw - 0.25, -hl + 0.8, grey(12))
    P.rect(-hw, -hl + 2.6, hw, hl, grey(40), grey(72), 2)
    for y in np.arange(-hl + 3.2, hl - 0.2, 1.1):
        P.line([(-hw + 0.05, y), (hw - 0.05, y)], grey(28), 0.1)
    P.line([(0, -hl + 2.7), (0, hl - 0.1)], grey(48), 0.05)
    P.grain(rng)
    P.save("vehicle_military_truck.png")


def container_body(P, x0, y0, x1, y1, v, rng, ribs=0.26):
    P.rect(x0, y0, x1, y1, grey(v), grey(min(v + 40, 110)), 2)
    for y in np.arange(y0 + 0.3, y1 - 0.2, ribs):
        P.line([(x0 + 0.08, y), (x1 - 0.08, y)], grey(max(v - 12, 6)), 0.05)
    c = 0.22
    for cx, cy in ((x0, y0), (x1 - c, y0), (x0, y1 - c), (x1 - c, y1 - c)):
        P.rect(cx, cy, cx + c, cy + c, grey(min(v + 55, 130)))


def container(name, length, v, rng):
    w = 2.44
    P = Pen(w, length, V_PX, pad_m=0.2)
    container_body(P, -w / 2, -length / 2, w / 2, length / 2, v, rng)
    P.grain(rng, 5)
    P.save(f"vehicle_{name}.png")


def container_truck(rng):
    length, w = 16.5, 2.5
    P = Pen(w, length, V_PX)
    hl, hw = length / 2, w / 2
    P.rect(-hw + 0.05, -hl, hw - 0.05, -hl + 2.4, grey(30), grey(72), 2, r=0.25)
    P.rect(-hw + 0.2, -hl + 0.12, hw - 0.2, -hl + 0.75, grey(12))
    P.rect(-0.9, -hl + 1.0, 0.9, -hl + 2.1, grey(38), grey(60), 1)
    P.rect(-0.5, -hl + 2.4, 0.5, -hl + 3.6, grey(16))
    container_body(P, -1.22, -hl + 3.9, 1.22, hl, 44, rng)
    P.grain(rng, 5)
    P.save("vehicle_container_truck.png")


def stall_canvas():
    return Pen(5.0, 5.0, S_PX, pad_m=0.0)


def goods(P, cx, cy, n, spread, rng, sizes=(0.12, 0.26)):
    for _ in range(n):
        x, y = cx + rng.uniform(-spread, spread), cy + rng.uniform(-spread, spread) * 0.6
        r = rng.uniform(*sizes)
        v = int(rng.choice([60, 80, 100, 130]))
        if rng.random() < 0.5:
            P.disc(x, y, r, grey(v), grey(30), 1)
        else:
            P.rect(x - r, y - r, x + r, y + r, grey(v), grey(30), 1)


def corrugated(P, pts, v, rng, along=True, step=0.16):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    P.poly(pts, grey(v), grey(v + 35), 2)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    if along:
        for x in np.arange(x0 + step, x1, step):
            P.line([(x, y0 + 0.05), (x, y1 - 0.05)], grey(max(v - 14, 5)), 0.03)


def stall_lean_to(rng, broken):
    P = stall_canvas()
    if not broken:
        P.rect(-1.5, -1.0, 1.5, -0.85, grey(24))
        corrugated(P, [(-1.6, -1.05), (1.6, -1.05), (1.6, 1.0), (-1.6, 1.0)], 52, rng)
        P.rect(-1.45, 0.85, 1.45, 1.15, grey(38), grey(70), 1)
        goods(P, 0, 1.0, 6, 1.2, rng, (0.08, 0.15))
    else:
        corrugated(P, [(-0.6, -1.2), (1.4, -0.9), (1.2, 0.6), (-0.8, 0.3)], 48, rng)
        corrugated(P, [(0.9, 0.2), (2.3, 0.5), (2.1, 1.5), (0.7, 1.2)], 44, rng)
        P.line([(-1.7, -0.8), (0.2, -1.6)], grey(60), 0.1)
        P.line([(-1.2, 1.1), (1.3, 1.6)], grey(60), 0.1)
        goods(P, 0.6, 0.9, 12, 1.8, rng, (0.08, 0.16))
    P.grain(rng, 4)
    return P


def stall_canopy(rng, broken):
    P = stall_canvas()
    if not broken:
        for i, x in enumerate(np.arange(-1.5, 1.5, 0.375)):
            P.rect(x, -1.5, x + 0.375, 1.5, grey(90 if i % 2 else 34))
        P.rect(-1.5, -1.5, 1.5, 1.5, None, grey(110), 2)
        for x, y in ((-1.45, -1.45), (1.45, -1.45), (-1.45, 1.45), (1.45, 1.45)):
            P.disc(x, y, 0.07, grey(20))
        goods(P, 0, 1.6, 5, 1.2, rng, (0.08, 0.15))
    else:
        pts = [(-0.9, -1.2), (1.8, -0.6), (1.4, 1.0), (0.2, 1.4), (-1.0, 0.4)]
        P.poly(pts, grey(34), grey(100), 2)
        for i, x in enumerate(np.arange(-0.9, 1.8, 0.375)):
            if i % 2:
                P.line([(x, -1.1), (x - 0.2, 1.2)], grey(90), 0.3)
        for (x0, y0), (x1, y1) in (((-2.0, -1.6), (-0.6, -2.1)), ((1.2, 1.7), (2.4, 1.0)),
                                   ((-1.8, 1.4), (-0.6, 2.0)), ((1.6, -1.9), (2.4, -0.8))):
            P.line([(x0, y0), (x1, y1)], grey(64), 0.07)
        goods(P, 0.8, 0.6, 10, 1.9, rng, (0.08, 0.16))
    P.grain(rng, 4)
    return P


def stall_table(rng, broken):
    P = stall_canvas()
    if not broken:
        P.rect(-1.25, -0.6, 1.25, 0.6, grey(58), grey(90), 2)
        for x in np.arange(-1.0, 1.2, 0.55):
            P.rect(x, -0.45, x + 0.42, 0.35, grey(34), grey(80), 1)
            goods(P, x + 0.21, -0.05, 3, 0.12, rng, (0.05, 0.09))
        for x in (-0.9, -0.2, 0.6):
            P.rect(x, -1.4, x + 0.55, -0.85, grey(44), grey(78), 1)
    else:
        P.poly([(-0.6, -0.9), (1.6, -0.4), (1.3, 0.7), (-0.9, 0.2)], grey(56), grey(88), 2)
        for x, y, a in ((-1.6, -1.2, 0.2), (1.9, 1.1, -0.3), (0.2, 1.5, 0.5), (2.1, -1.0, 0.1), (-1.2, 1.2, -0.4)):
            c, s = np.cos(a), np.sin(a)
            P.poly([(x + c * dx - s * dy, y + s * dx + c * dy) for dx, dy in
                    ((-0.25, -0.2), (0.25, -0.2), (0.25, 0.2), (-0.25, 0.2))], grey(36), grey(78), 1)
        goods(P, 0.6, 0.4, 16, 1.9, rng, (0.05, 0.1))
    P.grain(rng, 4)
    return P


def stall_hand_cart(rng, broken):
    P = stall_canvas()
    if not broken:
        P.rect(-1.0, -0.6, 1.0, 0.6, grey(46), grey(84), 2)
        for x in np.arange(-0.85, 0.9, 0.22):
            P.line([(x, -0.55), (x, 0.55)], grey(36), 0.04)
        P.rect(-0.3, -0.85, 0.3, -0.6, grey(18))
        P.rect(-0.3, 0.6, 0.3, 0.85, grey(18))
        P.line([(1.0, -0.4), (1.7, -0.45)], grey(70), 0.06)
        P.line([(1.0, 0.4), (1.7, 0.45)], grey(70), 0.06)
        goods(P, 0, 0, 7, 0.7, rng, (0.08, 0.17))
    else:
        P.poly([(-0.4, -1.0), (1.4, -0.4), (1.0, 0.7), (-0.8, 0.1)], grey(46), grey(84), 2)
        P.disc(-1.4, 0.9, 0.3, grey(18), grey(54), 2)
        P.line([(1.5, -1.3), (2.2, -0.4)], grey(70), 0.06)
        goods(P, 0.8, 0.6, 12, 1.7, rng, (0.08, 0.16))
    P.grain(rng, 4)
    return P


STALLS = {"lean_to": stall_lean_to, "canopy": stall_canopy, "table": stall_table, "hand_cart": stall_hand_cart}


def tanker(rng):
    """A rigid road tanker: cab, then a round-ended tank with bands, hatches
    and a walkway along its top."""
    length, w = 10.0, 2.5
    P = Pen(w, length, V_PX)
    hl, hw = length / 2, w / 2
    P.rect(-hw + 0.05, -hl, hw - 0.05, -hl + 2.2, grey(34), grey(76), 2, r=0.25)
    P.rect(-hw + 0.2, -hl + 0.12, hw - 0.2, -hl + 0.7, grey(12))
    P.rect(-hw + 0.25, -hl + 2.2, hw - 0.25, hl - 0.1, grey(18))
    P.rect(-hw + 0.12, -hl + 2.55, hw - 0.12, hl - 0.25, grey(58), grey(96), 2, r=1.0)
    for y in np.arange(-hl + 3.6, hl - 0.8, 1.5):
        P.line([(-hw + 0.14, y), (hw - 0.14, y)], grey(40), 0.08)
    P.rect(-0.22, -hl + 2.9, 0.22, hl - 0.6, grey(44), grey(70), 1)
    for y in (-hl + 3.9, 0.9, hl - 1.5):
        P.disc(0.0, y, 0.34, grey(72), grey(26), 2)
    P.grain(rng, 5)
    P.save("vehicle_tanker.png")


def dump_truck(rng):
    """A rigid tipper: cab under a canopy plate, then an open body with a
    thick rim and a load in it."""
    length, w = 8.5, 2.5
    P = Pen(w, length, V_PX)
    hl, hw = length / 2, w / 2
    P.rect(-hw + 0.05, -hl, hw - 0.05, -hl + 2.1, grey(40), grey(80), 2, r=0.25)
    P.rect(-hw + 0.2, -hl + 0.12, hw - 0.2, -hl + 0.7, grey(12))
    P.rect(-hw, -hl + 1.5, hw, -hl + 2.5, grey(50), grey(84), 2)
    P.rect(-hw, -hl + 2.5, hw, hl - 0.05, grey(46), grey(90), 2)
    P.rect(-hw + 0.22, -hl + 2.75, hw - 0.22, hl - 0.3, grey(20))
    for _ in range(46):
        x, y = rng.uniform(-hw + 0.4, hw - 0.4), rng.uniform(-hl + 3.0, hl - 0.6)
        P.disc(x, y, rng.uniform(0.12, 0.3), grey(int(rng.integers(26, 44))))
    for y in np.arange(-hl + 3.4, hl - 0.6, 1.2):
        P.line([(-hw, y), (-hw + 0.22, y)], grey(70), 0.08)
        P.line([(hw - 0.22, y), (hw, y)], grey(70), 0.08)
    P.grain(rng, 5)
    P.save("vehicle_dump_truck.png")


def bogies(P, hl, hw, inset=2.2):
    """Two bogie frames showing under a wagon's ends."""
    for y in (-hl + inset, hl - inset):
        P.rect(-hw - 0.08, y - 1.2, -hw + 0.1, y + 1.2, grey(14))
        P.rect(hw - 0.1, y - 1.2, hw + 0.08, y + 1.2, grey(14))


def couplers(P, hl):
    for y in (-hl - 0.35, hl):
        P.rect(-0.22, y, 0.22, y + 0.35, grey(22), grey(50), 1)


def metro_car(name, cab, rng):
    """A metro car seen from above: a long roof with a walkway, two air
    conditioning housings, a pantograph on the motor cars, and a driving cab
    with its windscreen at the front of a cab car."""
    length, w = 20.0, 2.9
    P = Pen(w, length, V_PX, pad_m=0.6)
    hl, hw = length / 2, w / 2
    couplers(P, hl)
    P.rect(-hw, -hl, hw, hl, grey(38), grey(84), 2, r=0.45 if cab else 0.15)
    P.rect(-hw + 0.25, -hl + 0.3, hw - 0.25, hl - 0.3, grey(46))
    for y in np.arange(-hl + 1.2, hl - 1.0, 2.4):
        P.line([(-hw + 0.08, y), (-hw + 0.08, y + 1.6)], grey(18), 0.12)
        P.line([(hw - 0.08, y), (hw - 0.08, y + 1.6)], grey(18), 0.12)
    for y in (-hl + 4.0, hl - 6.5):
        P.rect(-0.9, y, 0.9, y + 2.5, grey(30), grey(70), 1)
        for yy in np.arange(y + 0.3, y + 2.3, 0.3):
            P.line([(-0.75, yy), (0.75, yy)], grey(22), 0.05)
    P.line([(0, -hl + 1.0), (0, hl - 1.0)], grey(56), 0.05)
    if cab:
        P.rect(-hw + 0.2, -hl + 0.12, hw - 0.2, -hl + 0.9, grey(12), r=0.3)
        P.rect(-0.5, -hl + 1.1, 0.5, -hl + 1.6, grey(60))
    else:
        P.rect(-0.7, -1.5, 0.7, 1.5, grey(26), grey(64), 1)
        P.line([(-0.6, -1.2), (0.6, 1.2)], grey(70), 0.08)
        P.line([(0.6, -1.2), (-0.6, 1.2)], grey(70), 0.08)
        P.line([(-0.9, 0.0), (0.9, 0.0)], grey(80), 0.1)
    P.grain(rng, 5)
    P.save(f"vehicle_{name}.png")


def boxcar(rng):
    """A covered goods wagon: a ribbed roof with a running board."""
    length, w = 14.0, 3.0
    P = Pen(w, length, V_PX, pad_m=0.6)
    hl, hw = length / 2, w / 2
    couplers(P, hl)
    bogies(P, hl, hw)
    P.rect(-hw, -hl, hw, hl, grey(34), grey(78), 2)
    for y in np.arange(-hl + 0.5, hl - 0.3, 0.7):
        P.line([(-hw + 0.1, y), (hw - 0.1, y)], grey(24), 0.08)
    P.rect(-0.3, -hl + 0.3, 0.3, hl - 0.3, grey(52), grey(70), 1)
    P.rect(-hw - 0.05, -1.4, -hw + 0.12, 1.4, grey(60))
    P.grain(rng, 5)
    P.save("vehicle_boxcar.png")


def flatcar(name, loaded, rng):
    """A flat wagon: a planked deck on a side sill, with stanchion pockets,
    or carrying a 40 ft container."""
    length, w = 14.0, 2.9
    P = Pen(w, length, V_PX, pad_m=0.6)
    hl, hw = length / 2, w / 2
    couplers(P, hl)
    P.rect(-hw, -hl, hw, hl, grey(30), grey(70), 2)
    P.rect(-hw + 0.2, -hl + 0.2, hw - 0.2, hl - 0.2, grey(40))
    for x in np.arange(-hw + 0.45, hw - 0.2, 0.3):
        P.line([(x, -hl + 0.25), (x, hl - 0.25)], grey(30), 0.04)
    for y in np.arange(-hl + 1.0, hl - 0.5, 1.6):
        P.rect(-hw, y, -hw + 0.18, y + 0.25, grey(70))
        P.rect(hw - 0.18, y, hw, y + 0.25, grey(70))
    if loaded:
        container_body(P, -1.22, -6.095, 1.22, 6.095, int(rng.choice([36, 48, 60])), rng)
    P.grain(rng, 5)
    P.save(f"vehicle_{name}.png")


def hopper(rng):
    """An open hopper wagon: three bays heaped with stone, thick rims and
    cross beams."""
    length, w = 12.0, 3.0
    P = Pen(w, length, V_PX, pad_m=0.6)
    hl, hw = length / 2, w / 2
    couplers(P, hl)
    P.rect(-hw, -hl, hw, hl, grey(44), grey(88), 2)
    bays = np.linspace(-hl + 0.4, hl - 0.4, 4)
    for ya, yb in zip(bays[:-1], bays[1:]):
        P.rect(-hw + 0.25, ya + 0.15, hw - 0.25, yb - 0.15, grey(18))
        for _ in range(26):
            x, y = rng.uniform(-hw + 0.45, hw - 0.45), rng.uniform(ya + 0.4, yb - 0.4)
            P.disc(x, y, rng.uniform(0.1, 0.28), grey(int(rng.integers(30, 52))))
        P.line([(-hw, yb), (hw, yb)], grey(64), 0.14)
    P.grain(rng, 5)
    P.save("vehicle_hopper.png")


def railcars():
    """The rail vehicles (kind "railcar"), each with its own seed so they do
    not change the other placeholders."""
    os.makedirs(OUT, exist_ok=True)
    metro_car("metro_cab", True, np.random.default_rng(601))
    metro_car("metro_car", False, np.random.default_rng(602))
    boxcar(np.random.default_rng(603))
    flatcar("flatcar", False, np.random.default_rng(604))
    flatcar("flatcar_container", True, np.random.default_rng(605))
    hopper(np.random.default_rng(606))


H_PX = 24  # px per metre for huts
C_PX = 32  # px per metre for clutter


def hut_canvas():
    return Pen(8.0, 8.0, H_PX, pad_m=0.0)


def hut_roof(P, x0, y0, x1, y1, v, rng, ribs=0.0, rim=96):
    P.rect(x0 + 0.25, y0 + 0.3, x1 + 0.25, y1 + 0.3, (0, 0, 0, 90))
    P.rect(x0, y0, x1, y1, grey(v), grey(rim), 2)
    if ribs:
        for x in np.arange(x0 + ribs, x1 - 0.05, ribs):
            P.line([(x, y0 + 0.08), (x, y1 - 0.08)], grey(max(v - 12, 6)), 0.05)


def hut_wreck(P, w, h, v, rng, ribs=False):
    """A flattened hut: its roof in torn sheets, thrown about over a dark
    floor, with loose panels round it."""
    P.rect(-w / 2, -h / 2, w / 2, h / 2, grey(14), grey(40), 1)
    for _ in range(3):
        cx, cy = rng.uniform(-w / 3, w / 3), rng.uniform(-h / 3, h / 3)
        a = rng.uniform(0, np.pi)
        sw, sh = rng.uniform(0.3, 0.55) * w, rng.uniform(0.35, 0.7) * h
        c, s = np.cos(a), np.sin(a)
        pts = [(cx + c * x - s * y, cy + s * x + c * y) for x, y in
               ((-sw / 2, -sh / 2), (sw / 2, -sh / 2 + rng.uniform(-0.2, 0.2)), (sw / 2, sh / 2), (-sw / 2, sh / 2))]
        P.poly(pts, grey(int(v * rng.uniform(0.6, 0.9))), grey(80), 1)
        if ribs:
            P.line([pts[0], pts[2]], grey(max(v - 16, 6)), 0.06)
    for _ in range(7):
        x, y = rng.uniform(-w / 2 - 1.2, w / 2 + 1.2), rng.uniform(-h / 2 - 1.2, h / 2 + 1.2)
        a = rng.uniform(0, np.pi)
        n = rng.uniform(0.4, 1.1)
        P.line([(x, y), (x + np.cos(a) * n, y + np.sin(a) * n)], grey(int(rng.integers(40, 80))), rng.uniform(0.06, 0.2))


def hut_guard(rng, broken):
    P = hut_canvas()
    if broken:
        hut_wreck(P, 2.6, 2.6, 60, rng)
    else:
        hut_roof(P, -1.3, -1.3, 1.3, 1.3, 60, rng)
        P.rect(-0.9, -0.9, 0.9, 0.9, grey(68))
        P.disc(0.5, -0.5, 0.18, grey(24))
        P.rect(-0.4, 1.3, 0.4, 1.5, grey(30))
    P.grain(rng, 4)
    return P


def hut_cabin(rng, broken):
    P = hut_canvas()
    if broken:
        hut_wreck(P, 6.0, 2.5, 52, rng, ribs=True)
    else:
        hut_roof(P, -3.0, -1.25, 3.0, 1.25, 52, rng, ribs=0.5)
        P.rect(2.0, -0.6, 2.7, 0.1, grey(34), grey(84), 1)
        P.rect(-2.2, 1.25, -1.4, 1.42, grey(28))
    P.grain(rng, 4)
    return P


def hut_shed(rng, broken):
    P = hut_canvas()
    if broken:
        hut_wreck(P, 4.0, 3.0, 40, rng, ribs=True)
    else:
        hut_roof(P, -2.0, -1.5, 2.0, 1.5, 40, rng, ribs=0.22, rim=78)
        P.line([(-2.0, -0.2), (2.0, -0.2)], grey(70), 0.08)
    P.grain(rng, 4)
    return P


def hut_shelter(rng, broken):
    P = hut_canvas()
    if broken:
        hut_wreck(P, 3.2, 2.4, 66, rng)
    else:
        hut_roof(P, -1.6, -1.2, 1.6, 1.2, 66, rng)
        P.rect(-1.2, -0.8, -0.3, 0.0, grey(40), grey(88), 1)
        P.disc(0.8, 0.4, 0.3, grey(30), grey(84), 1)
        P.line([(1.6, 0.4), (2.4, 0.4)], grey(76), 0.14)
    P.grain(rng, 4)
    return P


def clutter_drums(rng):
    P = Pen(1.3, 1.3, C_PX, pad_m=0.1)
    P.rect(-0.62, -0.62, 0.62, 0.62, grey(30), grey(52), 1)
    for x in (-0.3, 0.3):
        for y in (-0.3, 0.3):
            P.disc(x, y, 0.27, grey(int(rng.integers(46, 78))), grey(22), 1)
            P.disc(x + 0.1, y - 0.08, 0.05, grey(18))
    return P


def clutter_pallets(rng):
    P = Pen(1.3, 1.1, C_PX, pad_m=0.1)
    P.rect(-0.6, -0.5, 0.6, 0.5, grey(58), grey(30), 1)
    for y in np.arange(-0.4, 0.5, 0.2):
        P.line([(-0.58, y), (0.58, y)], grey(40), 0.04)
    P.rect(-0.5, -0.42, 0.25, 0.3, grey(70), grey(36), 1)
    return P


def clutter_reel(rng):
    P = Pen(1.9, 1.2, C_PX, pad_m=0.1)
    P.rect(-0.7, -0.5, 0.7, 0.5, grey(44), grey(24), 1)
    for y in np.arange(-0.42, 0.5, 0.12):
        P.line([(-0.68, y), (0.68, y)], grey(30), 0.04)
    for x in (-0.82, 0.82):
        P.rect(x - 0.1, -0.6, x + 0.1, 0.6, grey(74), grey(34), 1)
    return P


def clutter_cylinders(rng):
    P = Pen(2.0, 1.0, C_PX, pad_m=0.1)
    P.rect(-1.0, -0.5, 1.0, 0.5, None, grey(70), 2)
    for x in np.arange(-0.75, 0.9, 0.3):
        for y in (-0.22, 0.22):
            P.disc(x, y, 0.13, grey(int(rng.integers(50, 86))), grey(24), 1)
    return P


def clutter_cabinet(rng):
    P = Pen(1.3, 0.6, C_PX, pad_m=0.1)
    P.rect(-0.55, -0.2, 0.75, 0.38, (0, 0, 0, 90))
    P.rect(-0.65, -0.3, 0.65, 0.3, grey(62), grey(98), 1)
    P.line([(0.0, -0.28), (0.0, 0.28)], grey(34), 0.04)
    return P


def clutter_hydrant(rng):
    P = Pen(0.9, 0.9, C_PX, pad_m=0.1)
    P.disc(0.06, 0.08, 0.3, (0, 0, 0, 90))
    for a in (0.0, 2.1, 4.2):
        P.line([(0, 0), (np.cos(a) * 0.4, np.sin(a) * 0.4)], grey(60), 0.16)
    P.disc(0, 0, 0.26, grey(84), grey(30), 1)
    P.disc(0, 0, 0.1, grey(40))
    return P


def clutter_sleepers(rng):
    P = Pen(3.0, 1.3, C_PX, pad_m=0.1)
    for y in np.arange(-0.55, 0.5, 0.26):
        dx = rng.uniform(-0.12, 0.12)
        P.rect(-1.4 + dx, y, 1.4 + dx, y + 0.22, grey(int(rng.integers(34, 56))), grey(20), 1)
    return P


def clutter_skid(rng):
    P = Pen(2.4, 1.2, C_PX, pad_m=0.1)
    P.rect(-1.2, -0.6, 1.2, 0.6, grey(28), grey(70), 1)
    P.rect(-1.0, -0.38, -0.1, 0.38, grey(56), grey(26), 1)
    P.disc(0.55, 0.0, 0.34, grey(64), grey(26), 1)
    P.line([(-0.1, 0.0), (0.25, 0.0)], grey(80), 0.14)
    P.line([(0.55, -0.34), (0.55, -0.58)], grey(80), 0.12)
    return P


CLUTTER = {"drums": clutter_drums, "pallets": clutter_pallets, "reel": clutter_reel, "cylinders": clutter_cylinders,
           "cabinet": clutter_cabinet, "hydrant": clutter_hydrant, "sleepers": clutter_sleepers, "skid": clutter_skid}


def hut_kiosk(rng, broken):
    P = hut_canvas()
    if broken:
        hut_wreck(P, 2.4, 1.8, 70, rng)
    else:
        hut_roof(P, -1.2, -0.9, 1.2, 0.9, 70, rng, rim=104)
        P.rect(-1.25, 0.75, 1.25, 1.25, grey(36), grey(90), 1)
        for x in np.arange(-1.0, 1.1, 0.4):
            P.disc(x, 1.0, 0.11, grey(int(rng.integers(50, 110))))
    P.grain(rng, 4)
    return P


def hut_tent(rng, broken):
    P = hut_canvas()
    if broken:
        hut_wreck(P, 5.0, 3.6, 56, rng)
    else:
        P.rect(-2.25, -1.5, 2.75, 2.1, (0, 0, 0, 90))
        P.poly([(-2.5, -1.8), (2.5, -1.8), (2.5, 0.0), (-2.5, 0.0)], grey(62), grey(92), 1)
        P.poly([(-2.5, 0.0), (2.5, 0.0), (2.5, 1.8), (-2.5, 1.8)], grey(46), grey(84), 1)
        P.line([(-2.5, 0.0), (2.5, 0.0)], grey(96), 0.1)
        for x in (-2.5, 2.5):
            for y in (-1.8, 1.8):
                P.line([(x, y), (x + (0.5 if x > 0 else -0.5), y + (0.5 if y > 0 else -0.5))], grey(80), 0.04)
    P.grain(rng, 4)
    return P


def clutter_rubbish(rng):
    P = Pen(2.2, 1.8, C_PX, pad_m=0.1)
    for _ in range(26):
        x, y = rng.normal(0, 0.45), rng.normal(0, 0.35)
        P.disc(x, y, rng.uniform(0.1, 0.3), grey(int(rng.integers(30, 90))))
    for _ in range(6):
        x, y = rng.normal(0, 0.5), rng.normal(0, 0.4)
        P.rect(x, y, x + rng.uniform(0.15, 0.4), y + rng.uniform(0.1, 0.3), grey(int(rng.integers(60, 120))))
    return P


def clutter_tyres(rng):
    P = Pen(1.8, 1.2, C_PX, pad_m=0.1)
    for x, y in ((-0.45, -0.15), (0.35, -0.2), (-0.05, 0.25)):
        P.disc(x, y, 0.38, grey(18), grey(46), 2)
        P.disc(x, y, 0.16, grey(40))
    return P


def clutter_crates(rng):
    P = Pen(1.8, 1.4, C_PX, pad_m=0.1)
    for x, y in ((-0.5, -0.35), (0.3, -0.35), (-0.1, 0.35)):
        v = int(rng.integers(56, 88))
        P.rect(x - 0.38, y - 0.3, x + 0.38, y + 0.3, grey(v), grey(30), 1)
        P.line([(x - 0.38, y - 0.3), (x + 0.38, y + 0.3)], grey(v - 22), 0.04)
    return P


def clutter_sacks(rng):
    P = Pen(1.6, 1.2, C_PX, pad_m=0.1)
    for _ in range(6):
        x, y = rng.uniform(-0.5, 0.5), rng.uniform(-0.35, 0.35)
        P.rect(x - 0.3, y - 0.2, x + 0.3, y + 0.2, grey(int(rng.integers(80, 110))), grey(50), 1, r=0.12)
    return P


def clutter_tarp(rng):
    P = Pen(2.6, 2.0, C_PX, pad_m=0.1)
    P.poly([(-1.25, -0.9), (1.2, -0.95), (1.3, 0.9), (-1.2, 0.95)], grey(44), grey(76), 1)
    for _ in range(3):
        y = rng.uniform(-0.7, 0.7)
        P.line([(-1.2, y), (1.2, y + rng.uniform(-0.2, 0.2))], grey(34), 0.05)
    return P


def clutter_washing(rng):
    P = Pen(3.2, 0.8, C_PX, pad_m=0.1)
    P.line([(-1.6, 0.0), (1.6, 0.0)], grey(70), 0.03)
    x = -1.4
    while x < 1.3:
        w = rng.uniform(0.25, 0.5)
        P.rect(x, -0.2, x + w, 0.25, grey(int(rng.integers(70, 140))))
        x += w + rng.uniform(0.05, 0.2)
    return P


def clutter_genset(rng):
    P = Pen(1.8, 1.0, C_PX, pad_m=0.1)
    P.rect(-0.8, -0.42, 0.8, 0.42, grey(40), grey(84), 1)
    P.rect(-0.6, -0.3, 0.1, 0.3, grey(26))
    P.disc(0.45, 0.0, 0.2, grey(60))
    return P


def clutter_haystack(rng):
    P = Pen(2.4, 2.4, C_PX, pad_m=0.1)
    P.disc(0.15, 0.15, 1.05, (0, 0, 0, 90))
    P.disc(0.0, 0.0, 1.05, grey(96), grey(60), 1)
    for _ in range(30):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.1, 0.95)
        P.line([(np.cos(a) * r, np.sin(a) * r), (np.cos(a) * (r + 0.15), np.sin(a) * (r + 0.15))], grey(70), 0.03)
    return P


def clutter_cart(rng):
    P = Pen(3.0, 1.6, C_PX, pad_m=0.1)
    P.rect(-0.9, -0.6, 1.0, 0.6, grey(54), grey(30), 1)
    for y in np.arange(-0.45, 0.5, 0.2):
        P.line([(-0.85, y), (0.95, y)], grey(42), 0.03)
    P.rect(-0.2, -0.78, 0.2, -0.6, grey(24))
    P.rect(-0.2, 0.6, 0.2, 0.78, grey(24))
    P.line([(1.0, -0.3), (1.5, 0.0), (1.0, 0.3)], grey(46), 0.06)
    return P


def clutter_jerrycans(rng):
    P = Pen(1.4, 1.0, C_PX, pad_m=0.1)
    for i in range(4):
        x = -0.5 + i * 0.33
        P.rect(x - 0.13, -0.3, x + 0.13, 0.3, grey(int(rng.integers(40, 70))), grey(90), 1)
    return P


def clutter_sandbags(rng):
    P = Pen(2.8, 1.0, C_PX, pad_m=0.1)
    for row, y in enumerate((-0.2, 0.2)):
        x = -1.3 + (0.25 if row else 0.0)
        while x < 1.2:
            P.rect(x, y - 0.18, x + 0.48, y + 0.18, grey(int(rng.integers(70, 96))), grey(40), 1, r=0.1)
            x += 0.5
    return P


CLUTTER2 = {"rubbish": clutter_rubbish, "tyres": clutter_tyres, "crates": clutter_crates, "sacks": clutter_sacks,
            "tarp": clutter_tarp, "washing": clutter_washing, "genset": clutter_genset, "haystack": clutter_haystack,
            "cart": clutter_cart, "jerrycans": clutter_jerrycans, "sandbags": clutter_sandbags}


def clutter_fuel_pump(rng):
    """A fuel dispenser: a narrow cabinet with a display on each face and a
    hose hanging at each end."""
    P = Pen(1.0, 0.6, C_PX, pad_m=0.15)
    P.rect(-0.38, -0.16, 0.5, 0.34, (0, 0, 0, 90))
    P.rect(-0.45, -0.25, 0.45, 0.25, grey(78), grey(120), 1, r=0.06)
    P.rect(-0.28, -0.2, 0.28, 0.2, grey(40), grey(96), 1)
    P.rect(-0.18, -0.12, 0.18, 0.0, grey(110))
    for s in (-1, 1):
        P.line([(s * 0.45, 0.05), (s * 0.55, 0.2), (s * 0.5, 0.3)], grey(24), 0.06)
    return P


def clutter_air_post(rng):
    """An air and water post: a small pillar with a coiled hose beside it."""
    P = Pen(0.7, 0.5, C_PX, pad_m=0.1)
    P.rect(-0.3, -0.15, -0.02, 0.15, grey(88), grey(130), 1)
    P.disc(0.18, 0.0, 0.17, None, grey(30), 2)
    P.disc(0.18, 0.0, 0.08, None, grey(30), 1)
    return P


def clutter_tyre_stack(rng):
    """Two stacks of old tyres seen from above, one taller than the other."""
    P = Pen(1.8, 0.95, C_PX, pad_m=0.1)
    for x, r in ((-0.42, 0.44), (0.44, 0.42)):
        P.disc(x + 0.06, 0.06, r, (0, 0, 0, 90))
        P.disc(x, 0.0, r, grey(20), grey(52), 2)
        P.disc(x, 0.0, r * 0.72, grey(28), grey(44), 1)
        P.disc(x, 0.0, r * 0.42, grey(46))
    return P


def clutter_engine(rng):
    """An engine block on a pallet: the block, its row of cylinder heads and
    the gearbox bell."""
    P = Pen(1.3, 0.85, C_PX, pad_m=0.1)
    P.rect(-0.65, -0.42, 0.65, 0.42, grey(58), grey(32), 1)
    for y in (-0.3, 0.0, 0.3):
        P.line([(-0.63, y), (0.63, y)], grey(40), 0.03)
    P.rect(-0.5, -0.24, 0.3, 0.24, grey(46), grey(100), 1)
    for x in np.arange(-0.38, 0.25, 0.2):
        P.disc(x, 0.0, 0.07, grey(90))
    P.disc(0.44, 0.0, 0.2, grey(38), grey(96), 1)
    return P


# The service sites' clutter (sites.py): gas stations and garages.
SITES_CLUTTER = {"fuel_pump": clutter_fuel_pump, "air_post": clutter_air_post, "tyre_stack": clutter_tyre_stack,
                 "engine": clutter_engine}


HUTS = {"guard": hut_guard, "cabin": hut_cabin, "shed": hut_shed, "shelter": hut_shelter,
        "kiosk": hut_kiosk, "tent": hut_tent}
CLUTTER.update(CLUTTER2)
CLUTTER.update(SITES_CLUTTER)


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(31)
    bus("bus_city", 12.0, False, rng)
    bus("bus_coach", 12.2, True, rng)
    tank("tank_west", 7.9, 3.66, 1.9, False, rng)
    tank("tank_east", 6.9, 3.6, 2.6, True, rng)
    apc(rng)
    military_truck(rng)
    container_truck(rng)
    container("container_20ft_a", 6.06, 44, rng)
    container("container_20ft_b", 6.06, 64, rng)
    container("container_40ft", 12.19, 36, rng)
    for i, (name, fn) in enumerate(STALLS.items()):
        for broken in (False, True):
            r = np.random.default_rng(100 + 2 * i + int(broken))
            fn(r, broken).save(f"stall_{name}{'_broken' if broken else ''}.png")
    tanker(np.random.default_rng(41))
    dump_truck(np.random.default_rng(42))
    for i, (name, fn) in enumerate(HUTS.items()):
        for broken in (False, True):
            fn(np.random.default_rng(200 + 2 * i + int(broken)), broken).save(f"hut_{name}{'_broken' if broken else ''}.png")
    for i, (name, fn) in enumerate(CLUTTER.items()):
        P = fn(np.random.default_rng(300 + i))
        P.grain(np.random.default_rng(400 + i), 4)
        P.save(f"clutter_{name}.png")
    railcars()
    print("wrote placeholders to", OUT)


if __name__ == "__main__":
    main()
