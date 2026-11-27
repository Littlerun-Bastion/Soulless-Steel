"""Small pieces of equipment drawn on the ground: the visuals of the ground
salvage sources (a transformer, a motor, a pump, cabinets, a valve, oil
drums, a cable drum, a diesel generator, a derelict tractor, a relay mast).
Each one shows what it gives, so one look tells the player what is there.

place(site_or_None, L, kind, x, y, ang, rng) draws one into the "interiors"
sublayer (over the halos, under mechas) and returns its outline box (width,
height in metres, along and across ang). add_source() also registers the
salvage source with that box.

All shapes are plain quads and discs, in greys a little brighter than the
ground, with light edges.
"""
import numpy as np
from shapely.geometry import Point

import style
from solar import Quads
from style import local_rect

SUB = "interiors"
EDGE_V = 0.42
SIZES = {
    "transformer": (4.0, 3.0), "electric_motor": (2.4, 1.4), "industrial_pump": (2.8, 1.6),
    "control_cabinet": (2.6, 1.0), "valve_assembly": (2.8, 1.3), "oil_drums": (2.6, 2.6),
    "cable_drum": (2.5, 1.7), "diesel_generator": (3.5, 1.6), "tractor": (4.4, 2.4),
    "relay_mast": (5.0, 5.0),
}


def disc(L, x, y, r, v, chunk, n=None, a=1.0):
    n = n or (8 if r < 0.4 else 12 if r < 1.2 else 20)
    L.fill(SUB, Point(x, y).buffer(r, quad_segs=max(2, n // 4)), v, a, chunk=chunk)


def ring(L, x, y, r, w, v, chunk):
    L.line(SUB, Point(x, y).buffer(r, quad_segs=5).exterior, w, v, chunk=chunk)


def shadow(Q, w, h, a=0.45):
    Q.grad(-w / 2 + 0.3, h / 2, w / 2 + 0.3, h / 2 + 0.6, 0.0, a, 0.0)
    Q.grad(w / 2, -h / 2 + 0.3, w / 2 + 0.6, h / 2 + 0.3, 0.0, a * 0.8, 0.0)


def outline(Q, x0, y0, x1, y1, v=EDGE_V, w=0.06):
    Q.line(x0, y0, x1, y0, w, v)
    Q.line(x1, y0, x1, y1, w, v)
    Q.line(x1, y1, x0, y1, w, v)
    Q.line(x0, y1, x0, y0, w, v)


def transformer(L, Q, rng, key):
    shadow(Q, 3.0, 2.2)
    for x in np.arange(-1.6, 1.65, 0.22):
        Q.line(x, -1.45, x, -1.1, 0.08, 0.3)
        Q.line(x, 1.1, x, 1.45, 0.08, 0.3)
    Q.rect(-1.5, -1.1, 1.5, 1.1, 0.24)
    outline(Q, -1.5, -1.1, 1.5, 1.1)
    Q.rect(-1.3, -0.8, -0.5, 0.8, 0.18)
    Q.flush(L, SUB, key)
    for i, xx in enumerate((-0.6, 0.2, 1.0)):
        p = Q.to_world(xx, 0.0)
        disc(L, p[0], p[1], 0.22, 0.5, key)
        ring(L, p[0], p[1], 0.22, 0.04, 0.12, key)


def motor(L, Q, rng, key, length=1.8, dia=1.0):
    shadow(Q, length + 0.4, dia + 0.2)
    Q.rect(-length / 2 - 0.2, -dia / 2 - 0.1, length / 2 + 0.2, dia / 2 + 0.1, 0.14)
    Q.rect(-length / 2, -dia / 2, length / 2, dia / 2, 0.3)
    for x in np.arange(-length / 2 + 0.15, length / 2 - 0.3, 0.12):
        Q.line(x, -dia / 2, x, dia / 2, 0.03, 0.22)
    Q.rect(length / 2 - 0.25, -dia / 2 - 0.05, length / 2, dia / 2 + 0.05, 0.38)
    Q.line(length / 2, 0, length / 2 + 0.35, 0, 0.12, 0.5)
    outline(Q, -length / 2, -dia / 2, length / 2, dia / 2)
    Q.flush(L, SUB, key)


def pump(L, Q, rng, key):
    shadow(Q, 2.6, 1.3)
    Q.rect(-1.3, -0.65, 1.3, 0.65, 0.14)
    Q.rect(-1.2, -0.4, 0.2, 0.4, 0.3)
    for x in np.arange(-1.1, 0.1, 0.12):
        Q.line(x, -0.4, x, 0.4, 0.03, 0.22)
    outline(Q, -1.2, -0.4, 0.2, 0.4)
    Q.line(0.2, 0, 0.55, 0, 0.12, 0.5)
    Q.line(0.75, -0.65, 0.75, -1.3, 0.3, 0.33)
    Q.flush(L, SUB, key)
    p = Q.to_world(0.8, 0.0)
    disc(L, p[0], p[1], 0.55, 0.34, key)
    ring(L, p[0], p[1], 0.55, 0.05, EDGE_V, key)
    disc(L, p[0], p[1], 0.18, 0.12, key)


def cabinets(L, Q, rng, key):
    n = int(rng.integers(2, 4))
    w = 0.8
    x0 = -n * w / 2
    shadow(Q, n * w, 0.8)
    for i in range(n):
        xa = x0 + i * w
        Q.rect(xa + 0.02, -0.4, xa + w - 0.02, 0.4, 0.27)
        Q.line(xa + w / 2, -0.38, xa + w / 2, 0.38, 0.03, 0.15)
        Q.rect(xa + 0.1, -0.3, xa + 0.3, -0.18, 0.5)
        outline(Q, xa + 0.02, -0.4, xa + w - 0.02, 0.4, w=0.04)
    Q.flush(L, SUB, key)


def valve(L, Q, rng, key):
    shadow(Q, 2.6, 0.6)
    Q.rect(-1.4, -0.32, 1.4, 0.32, 0.36)
    Q.line(-1.4, -0.16, 1.4, -0.16, 0.06, 0.52)
    for x in (-1.2, -0.25, 0.25, 1.2):
        Q.rect(x - 0.07, -0.45, x + 0.07, 0.45, 0.46)
    Q.rect(-0.25, -0.5, 0.25, 0.5, 0.3)
    Q.flush(L, SUB, key)
    p = Q.to_world(0.0, 0.0)
    ring(L, p[0], p[1], 0.55, 0.08, 0.5, key)
    for a in (0, np.pi / 3, 2 * np.pi / 3):
        Q.line(np.cos(a) * 0.55, np.sin(a) * 0.55, -np.cos(a) * 0.55, -np.sin(a) * 0.55, 0.04, 0.5)
    Q.flush(L, SUB, key)


def oil_drums(L, Q, rng, key):
    Q.rect(-1.2, -1.2, 1.2, 1.2, 0.13, 0.9)
    Q.flush(L, SUB, key)
    for i in range(3):
        for j in range(3):
            if rng.random() < 0.2:
                continue
            p = Q.to_world(-0.75 + i * 0.75 + rng.uniform(-0.05, 0.05), -0.75 + j * 0.75 + rng.uniform(-0.05, 0.05))
            disc(L, p[0] + 0.12, p[1] + 0.12, 0.33, 0.0, key, a=0.4)
            disc(L, p[0], p[1], 0.31, rng.choice([0.22, 0.28, 0.34]), key)
            ring(L, p[0], p[1], 0.31, 0.04, EDGE_V, key)
            disc(L, p[0] + 0.12, p[1] - 0.08, 0.05, 0.08, key)


def cable_drum(L, Q, rng, key):
    shadow(Q, 2.3, 1.4)
    Q.rect(-1.15, -0.7, -0.95, 0.7, 0.3)
    Q.rect(0.95, -0.7, 1.15, 0.7, 0.3)
    Q.rect(-0.95, -0.55, 0.95, 0.55, 0.2)
    for x in np.arange(-0.9, 0.95, 0.09):
        Q.line(x, -0.55, x + 0.05, 0.55, 0.035, 0.36)
    outline(Q, -1.15, -0.7, 1.15, 0.7)
    Q.flush(L, SUB, key)


def generator(L, Q, rng, key):
    shadow(Q, 3.2, 1.4)
    Q.rect(-1.6, -0.7, 1.6, 0.7, 0.22)
    outline(Q, -1.6, -0.7, 1.6, 0.7)
    for y in np.arange(-0.55, 0.6, 0.12):
        Q.line(1.05, y, 1.5, y, 0.04, 0.12)
    Q.rect(-1.4, -0.5, 0.6, 0.5, 0.27)
    Q.line(-1.4, 0.0, 0.6, 0.0, 0.03, 0.15)
    Q.flush(L, SUB, key)
    p = Q.to_world(-1.0, -0.3)
    disc(L, p[0], p[1], 0.16, 0.05, key)
    ring(L, p[0], p[1], 0.16, 0.04, 0.4, key)


def tractor(L, Q, rng, key):
    shadow(Q, 4.0, 2.0)
    for y in (-1.0, 0.75):
        Q.rect(-1.7, y, -0.4, y + 0.42, 0.06)
        for x in np.arange(-1.65, -0.45, 0.16):
            Q.line(x, y, x, y + 0.42, 0.04, 0.16)
    for y in (-0.8, 0.6):
        Q.rect(1.1, y, 1.8, y + 0.22, 0.08)
    Q.rect(-0.3, -0.45, 2.0, 0.45, 0.25)
    Q.rect(-1.5, -0.7, -0.2, 0.7, 0.2)
    Q.rect(-1.35, -0.55, -0.4, 0.55, 0.1)
    for x in np.arange(0.1, 1.9, 0.2):
        Q.line(x, -0.4, x, 0.4, 0.03, 0.18)
    outline(Q, -0.3, -0.45, 2.0, 0.45, 0.36)
    Q.line(0.3, -0.3, 0.3, -0.9, 0.12, 0.08)
    Q.flush(L, SUB, key)


def relay_mast(L, Q, rng, key):
    for a in (0, 2 * np.pi / 3, 4 * np.pi / 3):
        Q.line(0, 0, np.cos(a) * 2.4, np.sin(a) * 2.4, 0.04, 0.4)
        Q.rect(np.cos(a) * 2.4 - 0.15, np.sin(a) * 2.4 - 0.15, np.cos(a) * 2.4 + 0.15, np.sin(a) * 2.4 + 0.15, 0.3)
    pts = [(np.cos(a) * 0.7, np.sin(a) * 0.7) for a in (np.pi / 2, np.pi / 2 + 2 * np.pi / 3, np.pi / 2 + 4 * np.pi / 3)]
    for (xa, ya), (xb, yb) in zip(pts, pts[1:] + pts[:1]):
        Q.line(xa, ya, xb, yb, 0.12, 0.45)
        Q.line(xa, ya, 0, 0, 0.05, 0.35)
    Q.rect(1.0, -0.4, 2.0, 0.4, 0.22)
    outline(Q, 1.0, -0.4, 2.0, 0.4)
    Q.flush(L, SUB, key)


DRAW = {
    "transformer": transformer, "electric_motor": motor, "industrial_pump": pump,
    "control_cabinet": cabinets, "valve_assembly": valve, "oil_drums": oil_drums,
    "cable_drum": cable_drum, "diesel_generator": generator, "tractor": tractor,
    "relay_mast": relay_mast,
}


def footprint(kind, x, y, ang, pad=0.3):
    """The ground a piece of equipment covers (a shapely polygon)."""
    w, h = SIZES[kind]
    return local_rect(Point(x, y), np.degrees(ang), -w / 2 - pad, -h / 2 - pad, w / 2 + pad, h / 2 + pad)


def place(L, kind, x, y, ang, rng):
    """Draws one piece of equipment centred on (x, y), turned by ang
    (radians). Returns its (width, height)."""
    key = style.chunk_key(Point(x, y))
    Q = Quads(Point(x, y), np.degrees(ang))
    DRAW[kind](L, Q, rng, key)
    return SIZES[kind]


def add_source(salvage, L, kind, x, y, ang, rng, draw=True):
    """Draws the equipment (unless draw is False) and registers it as a
    salvage source on the ground. Returns whether the source was added (it
    is not in the border band or a KeepOut area); it is drawn either way."""
    w, h = place(L, kind, x, y, ang, rng) if draw else SIZES[kind]
    if salvage is None:
        return False
    return salvage.add(kind, x, y, ang, w + 0.6, h + 0.6)
